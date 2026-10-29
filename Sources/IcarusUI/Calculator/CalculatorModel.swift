#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// The Calculator's state and every action the two screens can take.
    ///
    /// It holds the four inputs the entry screen asks for — the window, the
    /// posture, the cover toggle and "staying the whole window" — and nothing
    /// else the user types: what to wear is the engine's answer, never a question
    /// (R15). Computing reads the cached forecast and only ever fetches when
    /// there is no cached curve at all, so changing a window costs no request
    /// (R1); the refresh button is the one deliberate fetch.
    ///
    /// No arithmetic lives here. `Planner` produces the result, `ExposureModel`
    /// attenuates a logged dose, `SunscreenSolver` re-solves the alternative, and
    /// this class only carries values between them and the store.
    @MainActor
    public final class CalculatorModel: ObservableObject {
        @Published public var window: Window
        @Published public var posture: Posture = .upAndAbout
        @Published public var cover = false
        @Published public var stay = false
        /// What the user is taken to have worn when they log this session.
        /// `.asPrescribed` only when the result prescribed a pair and that pair
        /// is the headline; the sheet sets `.alternative` when they pick another.
        @Published public var confirmedSunscreen: SunscreenConfirmation = .none
        @Published public private(set) var result: DoseResult?
        /// The forecast behind the result, kept so the result screen can show
        /// the place and the age for every outcome, including the ones with no
        /// number at all.
        @Published public private(set) var forecastStatus: ForecastResult? {
            didSet {
                if let zone = forecastStatus?.curve?.timeZone {
                    timeZone = zone
                }
            }
        }
        /// The zone the slot's times are shown in: the forecast place's, as on
        /// the Result and in History, because the forecast and its day belong
        /// to the place (screen review F1). The phone's until a forecast is
        /// cached.
        @Published public private(set) var timeZone: TimeZone = .current
        /// The name of the place the user typed, while the app is pinned to
        /// one; nil while it follows the phone. The result screen names the
        /// place by it (RES-3), and says "your location" otherwise (RES-2).
        @Published public private(set) var placeName: String?
        /// The one planned session this model owns. Computing again replaces it
        /// rather than adding a second (R45).
        public private(set) var plannedSessionID: UUID?

        let env: AppEnvironment

        public init(env: AppEnvironment) {
            self.env = env
            let start = Self.nextQuarterHour(after: env.clock())
            window = Window(start: start, end: start.addingTimeInterval(Self.defaultWindowSeconds))
        }

        /// Show the slot in the cached forecast's zone before anything is
        /// computed. Reads the cache only.
        public func loadTimeZone() async {
            if let zone = await env.forecast.cached().curve?.timeZone {
                timeZone = zone
            }
        }

        // MARK: - The request

        /// Everything one recommendation is computed from, assembled from the
        /// same sources the timer uses: the same profile, the same replayed
        /// state, the same staleness, the same intent and the same cover. The
        /// timer plans from `now` over the rest of the entered window, so the two
        /// screens can never disagree about anything but the span.
        ///
        /// It reads the cache and never fetches: a window the user drags must not
        /// cost a request.
        public func request(window: Window, firstSide: Side, now: Date) async throws -> PlanRequest {
            let answer = await env.location.location(now: now)
            let curve = await env.forecast.cached().curve
            // Onboarding saves a profile before any of this is reachable; the
            // starting profile is the same conservative Type III the history
            // store replays under, so a missing one is short, never a crash.
            let profile = env.profile.load() ?? AppEnvironment.startingProfile
            let state = try await env.history.state(now: now)
            return PlanRequest(
                curve: curve,
                forecastFailure: curve == nil ? failureKind(coordinate: answer.coordinate) : nil,
                deviceLocation: answer.coordinate,
                now: now,
                window: window,
                posture: posture,
                firstSide: firstSide,
                coverHeadAndShoulders: cover,
                intent: stay ? .stayWholeWindow : .bestMinutes,
                profile: profile,
                state: state,
                goal: TanningGoal()
            )
        }

        // MARK: - Computing

        /// The result for the entered window, and the planned session that goes
        /// with it.
        ///
        /// The cache answers first. Only an empty cache fetches, and only when
        /// there is a coordinate to fetch for; with neither the answer is the one
        /// outcome that shows no number, and the result screen still offers the
        /// manual place that would fix it (R2, R3).
        public func compute() async {
            let now = env.clock()
            let answer = await env.location.location(now: now)
            placeName = Self.placeName(of: answer)
            var status = await env.forecast.cached()
            if status.curve == nil, let coordinate = answer.coordinate {
                status = await env.forecast.current(for: coordinate, now: now)
            }
            forecastStatus = status

            guard answer.coordinate != nil else {
                confirmedSunscreen = .none
                result = Planner.plan(placelessRequest(curve: status.curve, now: now), tunables: env.tunables)
                return
            }
            do {
                let asked = try await request(window: window, firstSide: .faceUp, now: now)
                let planned = Planner.plan(asked, tunables: env.tunables)
                result = planned
                try await keepPlannedSession(planned, request: asked, now: now)
            } catch {
                // The history could not be read, so there is no state to plan
                // against. Showing the previous window's answer would be worse
                // than showing none: the screen falls back to the forecast line.
                result = nil
            }
        }

        /// Fetch the forecast on purpose, which is the only thing on either
        /// screen that does.
        public func refreshForecast() async {
            let now = env.clock()
            let answer = await env.location.location(now: now)
            placeName = Self.placeName(of: answer)
            guard let coordinate = answer.coordinate ?? env.lastCoordinate else {
                forecastStatus = await env.forecast.cached()
                return
            }
            forecastStatus = await env.forecast.current(for: coordinate, now: now, force: true)
        }

        /// The typed place's own name, which is the geocoder's data.
        private static func placeName(of answer: LocationAnswer) -> String? {
            if case let .manual(place) = answer {
                return place.name
            }
            return nil
        }

        /// Pin the app to a place the user typed, refetch for it, and answer
        /// again — the whole remedy for a denied location, in one call (R2).
        public func useManualPlace(_ place: Place) async {
            await env.location.useManual(place)
            await refreshForecast()
            await compute()
        }

        // MARK: - Logging

        /// "I did this": the planned session becomes logged, with the intervals
        /// the headline actually implies and the dose that goes with them (R45).
        ///
        /// A bare answer logs the block it solved. A sunscreened whole window
        /// logs the whole window, attenuated by the pair the user confirmed —
        /// never the raw whole window, which is a dose nobody received (R15).
        public func didThis() async throws {
            guard let result, let id = plannedSessionID,
                  case let .plan(plan, sunscreen, headline) = result.outcome
            else { return }

            let worn = wornChoice(headline: headline, sunscreen: sunscreen)
            var intervals = plan.intervals
            var doses = plan.perRegionDose
            if let worn {
                intervals = enteredWindowIntervals()
                doses = ExposureModel.attenuated(
                    result.wholeWindowRaw, sunscreen: worn, coverHeadAndShoulders: cover
                )
            }

            try await env.history.log(
                id,
                actual: intervals,
                sunscreen: worn,
                doses: doses,
                factors: result.targets.mapValues(\.adaptationFactor),
                targets: result.targets.mapValues(\.target)
            )
        }

        /// The pair the session is logged as wearing, or nil for a bare session.
        ///
        /// An alternative the user picked always counts. The prescribed pair
        /// counts only while it is the headline: a prescription the user never
        /// took up would otherwise credit them with a dose they did not receive,
        /// and an outcome with no realistic product confirms nothing at all.
        private func wornChoice(headline: Headline, sunscreen: SunscreenOutcome) -> SunscreenChoice? {
            switch confirmedSunscreen {
            case let .alternative(choice):
                choice
            case .asPrescribed:
                headline == .sunscreenForWholeWindow ? sunscreen.prescribedChoice : nil
            case .none:
                nil
            }
        }

        // MARK: - "I don't have that SPF"

        /// The re-solve for the product the user actually has, against the same
        /// region the prescription was solved on and what is left of its budget
        /// (R15). Nil when there is no plan to re-solve, which is when the sheet
        /// is not offered at all.
        public func alternative(have: SunscreenChoice) -> AlternativePlan? {
            guard let result, case .plan = result.outcome,
                  let region = result.attenuationRegion,
                  let target = result.targets[region],
                  let curve = forecastStatus?.curve
            else { return nil }
            let clipped = DoseCalculator.clip(window, toStartNoEarlierThan: env.clock()) ?? window
            return SunscreenSolver.alternative(
                have: have,
                rawSED: result.wholeWindowRaw[region] ?? 0,
                budgetSED: target.remaining,
                window: clipped,
                curve: curve,
                tunables: env.tunables
            )
        }

        // MARK: - Inside

        /// The request for a user whose place is unknown. The cached curve is
        /// still used when there is one — an old forecast for somewhere is more
        /// use than nothing — and the failure is named when there is not.
        private func placelessRequest(curve: ForecastCurve?, now: Date) -> PlanRequest {
            PlanRequest(
                curve: curve,
                forecastFailure: curve == nil ? .noLocation : nil,
                deviceLocation: nil,
                now: now,
                window: window,
                posture: posture,
                firstSide: .faceUp,
                coverHeadAndShoulders: cover,
                intent: stay ? .stayWholeWindow : .bestMinutes,
                profile: env.profile.load() ?? AppEnvironment.startingProfile,
                state: DerivedState.initial(tunables: env.tunables),
                goal: TanningGoal()
            )
        }

        /// Why there is no curve, in the engine's vocabulary. Not knowing where
        /// the user is comes first, because that is the one the user can fix.
        private func failureKind(coordinate: Coordinate?) -> IcarusCore.ForecastFailureKind {
            guard coordinate != nil else { return .noLocation }
            switch forecastStatus?.failure?.kind {
            case .some(.provider): return .provider
            case .some(.malformed): return .malformed
            case .some(.cacheUnreadable), .none: return .cacheUnreadable
            }
        }

        /// Store this result's session as the day's one planned session, and move
        /// the day's skin check to the end of the last session on it (R45).
        private func keepPlannedSession(_ result: DoseResult, request: PlanRequest, now: Date) async throws {
            guard case let .plan(plan, sunscreen, headline) = result.outcome, let curve = request.curve else {
                confirmedSunscreen = .none
                return
            }
            confirmedSunscreen = headline == .sunscreenForWholeWindow && sunscreen.prescribedChoice != nil
                ? .asPrescribed
                : .none

            let day = curve.day(window.start)
            let record = SessionRecord(
                id: UUID(),
                day: day,
                createdAt: now,
                plannedWindow: window,
                plannedIntervals: plan.intervals,
                firstSide: .faceUp,
                actualIntervals: nil,
                posture: posture,
                coverHeadAndShoulders: cover,
                intent: request.intent,
                ceilingAtPlan: request.profile.ceiling,
                manualMultiplierAtPlan: request.profile.manualMultiplier,
                prescribedSunscreen: sunscreen.prescribedChoice,
                sunscreen: nil,
                state: .planned,
                dosePerRegion: [:],
                factorsShown: result.targets.mapValues(\.adaptationFactor),
                targetsShown: result.targets.mapValues(\.target),
                curveUsed: curve.stored(for: day),
                forecastFetchedAt: curve.fetchedAt,
                forecastPlace: curve.location
            )
            let stored = try await env.history.upsertPlanned(record, replacing: plannedSessionID)
            plannedSessionID = stored
            try await env.prompts.sessionsChanged(on: day, lastSessionEnd: lastEnd(on: day, notCounting: stored))
        }

        /// The end of the day's last session: this one, or a later one the user
        /// already has. A discarded session is not one of them.
        private func lastEnd(on day: DayKey, notCounting stored: UUID) async throws -> Date {
            let others = try await env.history.sessions(on: day)
                .filter { $0.id != stored && $0.state != .discarded }
                .map { $0.actualWindow?.end ?? $0.plannedWindow.end }
            return ([window.end] + others).max() ?? window.end
        }

        /// The entered window as the intervals a sunscreened session runs: half
        /// each side in side order when lying down, one stretch when up and
        /// about (D-2026-09-03-F8 puts face up first without the timer).
        private func enteredWindowIntervals() -> [ExposureInterval] {
            guard posture == .lyingTurning else {
                return [ExposureInterval(exposure: .upAndAbout, window: window)]
            }
            let middle = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start) / 2)
            return [
                ExposureInterval(exposure: .lying(.faceUp), window: Window(start: window.start, end: middle)),
                ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: window.end)),
            ]
        }

        /// One hour, which is the window most people mean when they open the app.
        private static let defaultWindowSeconds: TimeInterval = 3600

        /// The first quarter hour strictly after `date`: a window the user can
        /// read off a clock, and never one that has already started.
        private static func nextQuarterHour(after date: Date) -> Date {
            let quarter = 900.0
            let seconds = date.timeIntervalSinceReferenceDate
            return Date(timeIntervalSinceReferenceDate: (seconds / quarter).rounded(.down) * quarter + quarter)
        }
    }
#endif
