#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// Something the skin check cannot answer for the user.
    public enum SkinCheckError: Error, Equatable {
        /// "As prescribed" on a session that never carried a prescription. The
        /// flow must offer another product or none instead of inventing a pair.
        case noPrescription(UUID)
    }

    /// One day's skin check: the sessions still to account for, the four answers
    /// R20 asks for, and the one report they become.
    ///
    /// It decides nothing about the calibration. `ExposureModel` turns the
    /// intervals the user confirmed into a dose, the store folds the report into
    /// the history, and `Replay` says what that did — this class only carries the
    /// answers between them and remembers what the day already holds.
    @MainActor
    public final class SkinCheckModel: ObservableObject {
        /// The day's sessions that are still planned: each one an unanswered
        /// "did you do this session?". A session leaves the list once it is
        /// logged or discarded.
        @Published public private(set) var planned: [SessionRecord] = []
        @Published public var answer: SkinAnswer?
        @Published public var timing: RednessTiming?
        @Published public var region: ReportRegion = .allExposed
        @Published public var confounders: Set<Confounder> = []
        /// True once the day has a logged session — the day's own record, not
        /// only what this flow logged, because the session may have been logged
        /// from the Calculator at the time.
        @Published public private(set) var hasLoggedSession = false

        public let day: DayKey
        let env: AppEnvironment
        private let channel: Channel

        public init(env: AppEnvironment, day: DayKey, channel: Channel) {
            self.env = env
            self.day = day
            self.channel = channel
            Task { await load() }
        }

        /// Read the day out of the store: what is still planned, and whether
        /// anything on it is logged. The initializer starts this; a caller that
        /// needs the answer before it acts awaits it.
        public func load() async {
            let sessions = await (try? env.history.sessions(on: day)) ?? []
            planned = sessions.filter { $0.state == .planned }
            hasLoggedSession = sessions.contains { $0.state == .logged }
        }

        // MARK: - Did you do this session?

        /// "Yes": the planned session becomes logged, over the intervals the
        /// user confirmed and with the dose the pair they wore actually let
        /// through (R22, R45).
        ///
        /// The dose is the sum over the intervals, attenuated once at the end,
        /// so an editable interval list and a sunscreen answer meet in exactly
        /// the one attenuation function every other logging path uses.
        public func didDo(_ id: UUID, actual: [ExposureInterval], wore: SunscreenConfirmation) async throws {
            let record = try await session(id)
            let choice = try resolve(wore, on: record)
            let curve = try record.curveUsed.curve()
            var bare = [Region: SED]()
            for interval in actual {
                let received = ExposureModel.dose(
                    interval.exposure,
                    coverHeadAndShoulders: record.coverHeadAndShoulders,
                    over: interval.window,
                    curve: curve,
                    tunables: env.tunables
                )
                for (region, dose) in received {
                    bare[region, default: 0] += dose
                }
            }
            let doses = ExposureModel.attenuated(
                bare, sunscreen: choice, coverHeadAndShoulders: record.coverHeadAndShoulders
            )
            try await env.history.log(
                id,
                actual: actual,
                sunscreen: choice,
                doses: doses,
                factors: record.factorsShown,
                targets: record.targetsShown
            )
            planned.removeAll { $0.id == id }
            hasLoggedSession = true
        }

        /// "No": a session that was planned and never happened is discarded, so
        /// it counts towards no total and no report (R45).
        public func didNotDo(_ id: UUID) async throws {
            try await env.history.discard(id)
            planned.removeAll { $0.id == id }
        }

        // MARK: - Submitting

        /// Everything the report needs is answered: the day has something to be
        /// evidence about, Q1 is answered, and Q2 is answered whenever Q1 named
        /// any redness at all.
        public var canSubmit: Bool {
            guard hasLoggedSession, let answer else { return false }
            return answer == .normal || timing != nil
        }

        /// Write the day's one report and say what it did to the calibration.
        ///
        /// The store refuses a second report for a day, so a flow submitted
        /// twice throws rather than merging. Recording the report is also what
        /// schedules the lasting-colour question, days after this answer and
        /// never after the session (R14).
        public func submit(now: Date) async throws -> CalibrationEffect {
            // Q1 is what a report is; the flow's submit is unreachable until it
            // is answered, so an unanswered one is a cancelled submit rather
            // than a state the store should ever see.
            guard let answer else { throw CancellationError() }
            let report = SkinReport(
                id: UUID(),
                day: day,
                reportedAt: now,
                answer: answer,
                timing: timing,
                region: region,
                confounders: confounders,
                channel: channel,
                lastingColour: nil,
                lastingColourAt: nil
            )
            let effect = try await env.history.addReport(report)
            await env.prompts.reportAdded(on: day, at: now)
            return effect
        }

        // MARK: - The confirmation

        /// The line the user is shown for what their report actually did.
        ///
        /// Three effects have their own words: the clamp asks them to revisit
        /// their skin type, a blister correction suggests the pause, and
        /// immediate darkening explains itself. A day with nothing logged says
        /// so. Everything else is "report saved".
        public static func confirmationKey(for effect: CalibrationEffect) -> CopyKey {
            switch effect {
            case .clampHit: .revisitSkinType
            case .blisterCorrection: .pauseSuggested
            case .reclassifiedAsNormal: .immediateDarkeningExplained
            case .noDoseThatDay: .noSessionToReport
            case .none, .discounted, .tanStateCredited, .multiplierMoved: .reportRecorded
            }
        }

        /// The values that line's placeholders take. Only two effects carry a
        /// number: the credited amount and the pause. The rest fill `{effect}`
        /// with nothing, because there is no approved wording for "the
        /// multiplier moved" and an invented sentence would be copy the owner
        /// never saw (R42).
        public static func confirmationArgs(for effect: CalibrationEffect) -> [String: String] {
            switch effect {
            case let .tanStateCredited(_, amount):
                ["effect": String(format: "%.2f", amount)]
            case let .blisterCorrection(_, _, pauseDays):
                ["pauseDays": String(pauseDays)]
            default:
                ["effect": ""]
            }
        }

        // MARK: - Inside

        /// The pair the session is logged as wearing. "As prescribed" is the
        /// record's own prescription and nothing else: a session that never
        /// carried one cannot be logged against it.
        private func resolve(_ wore: SunscreenConfirmation, on record: SessionRecord) throws -> SunscreenChoice? {
            switch wore {
            case .asPrescribed:
                guard let prescribed = record.prescribedSunscreen else {
                    throw SkinCheckError.noPrescription(record.id)
                }
                return prescribed
            case let .alternative(choice):
                return choice
            case .none:
                return nil
            }
        }

        private func session(_ id: UUID) async throws -> SessionRecord {
            if let known = planned.first(where: { $0.id == id }) {
                return known
            }
            guard let stored = try await env.history.sessions(on: day).first(where: { $0.id == id }) else {
                throw HistoryError.unknownSession(id)
            }
            return stored
        }
    }
#endif
