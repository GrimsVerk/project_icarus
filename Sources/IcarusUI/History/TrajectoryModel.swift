#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// One region's cumulative dose at the end of one logged session.
    ///
    /// `id` is the instant the session ended, which is what the chart plots on
    /// the x axis. Three regions share that instant, so the identity the chart
    /// actually draws with is the whole point — hence `Hashable` beside the
    /// declared `Identifiable`.
    public struct TrajectoryPoint: Sendable, Equatable, Hashable, Identifiable {
        public let id: Date
        public let region: Region
        public let cumulativeSED: SED

        public init(id: Date, region: Region, cumulativeSED: SED) {
            self.id = id
            self.region = region
            self.cumulativeSED = cumulativeSED
        }
    }

    /// The dose trajectory of the current tan cycle, per region (R24).
    ///
    /// It is a record of dose and nothing else: the numbers are the doses the
    /// history already stores, added up, and no pigment is claimed or plotted
    /// anywhere in this file. The title the chart carries says so.
    ///
    /// The cycle is the engine's, never this screen's: each region's
    /// `cycleStart` comes from the replayed state, and a session that ended
    /// before its region's cycle opened is not part of that region's trajectory
    /// and is skipped. So the running sum restarts at each cycle start, region
    /// by region, and inside a cycle it only ever rises.
    @MainActor
    public final class TrajectoryModel: ObservableObject {
        /// Every point of the current cycle, oldest session first and in region
        /// order within a session. Empty until `reload`.
        @Published public private(set) var points: [TrajectoryPoint] = []

        /// The cumulative dose at which each region first earned the escalation
        /// notice in this cycle — the line the chart marks. A region that has
        /// not earned one is absent.
        ///
        /// This is not guessed at from the dose: the notice is
        /// `AdaptationModel`'s own answer about the state replayed to the
        /// instant the session ended, and this only records the dose that stood
        /// at the first instant it said yes.
        @Published public private(set) var noticeSED: [Region: SED] = [:]

        let env: AppEnvironment

        public init(env: AppEnvironment) {
            self.env = env
        }

        /// Rebuild the trajectory from the record.
        ///
        /// A store that cannot be read leaves an empty chart rather than a
        /// crash: History is a record screen, and nothing here is a figure the
        /// user acts on.
        public func reload(now: Date) async {
            guard let history = try? await env.history.history(),
                  let state = try? await env.history.state(now: now)
            else {
                points = []
                noticeSED = [:]
                return
            }
            let skinType = (env.profile.load() ?? AppEnvironment.startingProfile).skinType
            var running = [Region: SED]()
            var built = [TrajectoryPoint]()
            var notices = [Region: SED]()

            for session in ended(in: history) {
                guard let end = session.actualWindow?.end, end <= now else { continue }
                for region in Region.allCases {
                    guard let opens = cycleOpens(region, in: state), end >= opens else { continue }
                    let total = running[region, default: 0] + (session.dosePerRegion[region] ?? 0)
                    running[region] = total
                    built.append(TrajectoryPoint(id: end, region: region, cumulativeSED: total))
                    if notices[region] == nil, await noticeRisen(region, at: end, skinType: skinType) {
                        notices[region] = total
                    }
                }
            }
            points = built
            noticeSED = notices
        }

        // MARK: - Inside

        /// The logged sessions that actually faced something, oldest end first.
        /// A planned or discarded session is not a record of dose and never
        /// reaches the chart.
        private func ended(in history: History) -> [SessionRecord] {
            history.sessions
                .filter { $0.state == .logged && $0.actualWindow != nil }
                .sorted { ($0.actualWindow?.end ?? .distantPast) < ($1.actualWindow?.end ?? .distantPast) }
        }

        /// When this region's current cycle opened. The region's own
        /// `cycleStart` is the answer; a region the replay left outside a cycle
        /// falls back to the most recent cycle start the state records, and a
        /// history with neither has no cycle to plot.
        private func cycleOpens(_ region: Region, in state: DerivedState) -> Date? {
            if let day = state.regions[region]?.cycleStart {
                return day.start()
            }
            return state.cycleStarts.last
        }

        /// Whether the region had earned the "tolerance has risen" notice at
        /// that instant, replayed to it.
        private func noticeRisen(_ region: Region, at end: Date, skinType: SkinType) async -> Bool {
            guard let state = try? await env.history.state(now: end),
                  let regionState = state.regions[region],
                  let notice = AdaptationModel.escalationNotice(
                      regionState,
                      now: end,
                      skinType: skinType,
                      tunables: env.tunables
                  )
            else { return false }
            if case .risen = notice {
                return true
            }
            return false
        }
    }
#endif
