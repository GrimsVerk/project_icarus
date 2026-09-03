#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// Why the timer would not start.
    ///
    /// Both are refusals rather than failures: the engine had no session to run,
    /// or the system will not let us alert with the screen locked (R11). The
    /// second one is offered again through `start(now:ignoringNotifications:)`,
    /// because a user who has read the warning may still want the clock.
    public enum TimerError: Error, Equatable {
        case cannotStart(Outcome)
        case notificationsDenied
    }

    /// Where the timer is. `running` carries what the user is doing now, when
    /// that stops being true, and when the whole session ends; `finished` says
    /// whether it was the midnight rule that stopped it (R11).
    public enum TimerPhase: Sendable, Equatable {
        case idle
        case running(exposure: Exposure, endsAt: Date, sessionEnd: Date)
        case finished(stoppedAtPlannedEnd: Bool)
    }

    /// The session clock for a lying-down session (R11).
    ///
    /// It plans nothing of its own: the calculator builds the request — same
    /// profile, same replayed state, same stale level, same maintenance scaling —
    /// and this model only moves the window to start at the real clock time and
    /// hands it to the `Planner`. The session is logged at the start from the
    /// plan's intervals (R45), and logged again, in place, from the intervals it
    /// actually ran when it stops.
    ///
    /// With the prescribed sunscreen confirmed the session is meant to span the
    /// covered window rather than the bare one, so every target is scaled by the
    /// pair's effective SPF before the solve: the same skin budget, reached
    /// through sunscreen, takes about `effectiveSPF` times as long. The dose
    /// written to the history is attenuated by that same pair, so what the skin
    /// is credited with is the target, not the raw window.
    @MainActor
    public final class FlipTimerModel: ObservableObject {
        private let env: AppEnvironment
        private let calculator: CalculatorModel

        /// Which way up the user starts. Face up by default (D-2026-09-03-F8).
        @Published public var firstSide: Side = .faceUp
        @Published public private(set) var phase: TimerPhase = .idle

        /// True once the system has told us it will not deliver alerts. False
        /// until something has asked, which is what `start` does.
        @Published public private(set) var notificationsDenied = false

        // What the running session was planned from, kept so a stop can write
        // the part of it that actually happened without planning again.
        private var plan: ExposurePlan?
        private var intervals: [ExposureInterval] = []
        private var curve: ForecastCurve?
        private var targets: [Region: RegionTarget] = [:]
        private var choice: SunscreenChoice?
        private var cover = false
        private var sessionID: UUID?

        public init(env: AppEnvironment, calculator: CalculatorModel) {
            self.env = env
            self.calculator = calculator
        }

        // MARK: - Starting

        /// Plan from the real clock and start the session (R11, R45).
        public func start(now: Date) async throws {
            try await start(now: now, ignoringNotifications: false)
        }

        /// The same start, with the notification refusal waived.
        ///
        /// The view offers this after showing `timerNeedsNotifications`: the
        /// warning is what R11 requires, not a veto.
        public func start(now: Date, ignoringNotifications: Bool) async throws {
            let entered = calculator.window
            let ahead = Window(start: now, end: max(now, entered.end))
            let confirmed = confirmedChoice()
            let request = try await scaled(
                calculator.request(window: ahead, firstSide: firstSide, now: now),
                by: confirmed
            )
            let result = Planner.plan(request, tunables: env.tunables)
            guard case let .plan(solved, sunscreen, _) = result.outcome else {
                throw TimerError.cannotStart(result.outcome)
            }
            if !ignoringNotifications {
                let allowed = await env.prompts.authorization()
                notificationsDenied = allowed == .denied
                if notificationsDenied {
                    throw TimerError.notificationsDenied
                }
            }
            remember(solved, request: request, result: result, choice: confirmed)
            try await logPlanned(solved, result: result)
            await schedule(solved, sunscreen: sunscreen)
            enter(solved)
        }

        // MARK: - Running

        /// Move the phase on to where `now` sits: the second side after the
        /// flip, and finished at the planned end.
        public func tick(now: Date) {
            guard case let .running(_, _, sessionEnd) = phase else { return }
            guard now < sessionEnd else {
                phase = .finished(stoppedAtPlannedEnd: false)
                return
            }
            guard let current = intervals.last(where: { $0.window.start <= now }) ?? intervals.first else { return }
            phase = .running(exposure: current.exposure, endsAt: current.window.end, sessionEnd: sessionEnd)
        }

        /// The app came back while the timer was running.
        ///
        /// A timer still running after the session's local midnight is stopped at
        /// its planned end and says so (R11): the minutes between the planned end
        /// and the small hours were not spent in the sun, so they are never
        /// credited.
        public func foregrounded(now: Date) async {
            guard case .running = phase, let plan, let curve else { return }
            let midnight = curve.day(plan.span.start).end()
            guard now >= midnight else {
                tick(now: now)
                return
            }
            try? await write(upTo: plan.span.end)
            await env.prompts.cancelTimer()
            phase = .finished(stoppedAtPlannedEnd: true)
        }

        /// Stop now: the session is logged from the intervals it actually ran,
        /// and every alert about it is cancelled (R11).
        public func stop(now: Date) async throws {
            try await write(upTo: now)
            await env.prompts.cancelTimer()
            phase = .finished(stoppedAtPlannedEnd: false)
        }

        // MARK: - Inside

        /// The pair the session is being run under: the prescribed one when the
        /// user confirmed it, the one they said they had instead, or none.
        private func confirmedChoice() -> SunscreenChoice? {
            switch calculator.confirmedSunscreen {
            case .asPrescribed:
                guard case let .plan(_, sunscreen, _) = calculator.result?.outcome else { return nil }
                return sunscreen.prescribedChoice
            case let .alternative(choice):
                return choice
            case .none:
                return nil
            }
        }

        /// The same request with every target scaled by the sunscreen's
        /// effective SPF, so the plan spans the covered window rather than the
        /// bare one. Unscaled when there is no sunscreen to plan under.
        private func scaled(_ request: PlanRequest, by choice: SunscreenChoice?) -> PlanRequest {
            guard let choice, choice.effectiveSPF > 0 else { return request }
            return PlanRequest(
                curve: request.curve,
                forecastFailure: request.forecastFailure,
                deviceLocation: request.deviceLocation,
                now: request.now,
                window: request.window,
                posture: request.posture,
                firstSide: request.firstSide,
                coverHeadAndShoulders: request.coverHeadAndShoulders,
                intent: request.intent,
                profile: request.profile,
                state: request.state,
                goal: ScaledGoal(base: request.goal, factor: choice.effectiveSPF)
            )
        }

        private func remember(
            _ solved: ExposurePlan,
            request: PlanRequest,
            result: DoseResult,
            choice: SunscreenChoice?
        ) {
            plan = solved
            intervals = solved.intervals
            curve = request.curve
            targets = result.targets
            cover = request.coverHeadAndShoulders
            self.choice = choice
        }

        /// Log the session the moment it starts, from the plan's own intervals:
        /// a session that is being run is a logged session, not a planned one
        /// (R45). A stop writes the same record again, shorter.
        private func logPlanned(_ solved: ExposurePlan, result _: DoseResult) async throws {
            guard let id = calculator.plannedSessionID else { return }
            sessionID = id
            let doses = ExposureModel.attenuated(
                solved.perRegionDose, sunscreen: choice, coverHeadAndShoulders: cover
            )
            try await log(intervals: solved.intervals, doses: doses, id: id)
        }

        private func schedule(_ solved: ExposurePlan, sunscreen: SunscreenOutcome) async {
            let sideEnd = solved.sides.count > 1 ? solved.sides.first?.window.end : nil
            var reapply = [Date]()
            if case let .prescribe(advice) = sunscreen {
                reapply = advice.reapplyAt.filter { $0 > solved.span.start && $0 < solved.span.end }
            }
            await env.prompts.scheduleTimer(
                sideEnd: sideEnd, reapply: reapply, sessionEnd: solved.span.end
            )
        }

        private func enter(_ solved: ExposurePlan) {
            let first = solved.intervals.first
            phase = .running(
                exposure: first?.exposure ?? .upAndAbout,
                endsAt: first?.window.end ?? solved.span.end,
                sessionEnd: solved.span.end
            )
        }

        /// Write what was actually faced up to `cutoff`: the plan's intervals
        /// clipped there, the dose those intervals delivered over the same
        /// curve, attenuated by the pair the session ran under.
        private func write(upTo cutoff: Date) async throws {
            guard let id = sessionID, let curve else { return }
            let ran = intervals.compactMap { clip($0, at: cutoff) }
            var raw = [Region: SED]()
            for interval in ran {
                let part = ExposureModel.dose(
                    interval.exposure, coverHeadAndShoulders: cover,
                    over: interval.window, curve: curve, tunables: env.tunables
                )
                for (region, dose) in part {
                    raw[region, default: 0] += dose
                }
            }
            let doses = ExposureModel.attenuated(raw, sunscreen: choice, coverHeadAndShoulders: cover)
            try await log(intervals: ran, doses: doses, id: id)
        }

        private func log(intervals: [ExposureInterval], doses: [Region: SED], id: UUID) async throws {
            try await env.history.log(
                id,
                actual: intervals,
                sunscreen: choice,
                doses: doses,
                factors: targets.mapValues(\.adaptationFactor),
                targets: targets.mapValues(\.target)
            )
        }

        /// The part of an interval that had happened by `cutoff`. Nil for one
        /// that never started, or that ends where it begins.
        private func clip(_ interval: ExposureInterval, at cutoff: Date) -> ExposureInterval? {
            guard interval.window.start < cutoff else { return nil }
            let window = Window(start: interval.window.start, end: min(interval.window.end, cutoff))
            guard window.minutes > 0 else { return nil }
            return ExposureInterval(exposure: interval.exposure, window: window)
        }
    }

    /// A goal whose every target is another goal's, scaled.
    ///
    /// This is how the sunscreened session is planned: the skin's budget has not
    /// changed, but reaching it through a product that divides the dose takes
    /// `factor` times as long, so the solve is given targets `factor` times as
    /// large and the dose it produces is divided by the same number before it is
    /// written. Scaling the goal rather than editing the request keeps the
    /// planner's own order — staleness, plateau, targets, solve — intact.
    struct ScaledGoal: TargetGoal {
        let base: any TargetGoal
        let factor: Double

        var copyKey: CopyKey {
            base.copyKey
        }

        // The seam's six arguments are `TargetGoal`'s, not ours.
        // swiftlint:disable:next function_parameter_count
        func target(
            for region: Region,
            profile: Profile,
            state: DerivedState,
            now: Date,
            stale: Bool,
            tunables: Tunables
        ) -> RegionTarget {
            base.target(
                for: region, profile: profile, state: state, now: now, stale: stale, tunables: tunables
            ).scaled(by: factor)
        }
    }
#endif
