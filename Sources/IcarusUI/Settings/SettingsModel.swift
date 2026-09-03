#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// Everything Settings can change and everything it has to say about the
    /// state (R7, R21, R25, R44).
    ///
    /// Nothing here is stored twice: the ceiling and the manual multiplier live
    /// in the profile, and every sentence about sensitivity is read from the
    /// state replayed out of the history. Because that replay lives behind an
    /// actor, the model holds a snapshot of it and refreshes the snapshot
    /// whenever it changes something — the properties the screen reads are
    /// synchronous, as the contract declares them.
    @MainActor
    public final class SettingsModel: ObservableObject {
        private let env: AppEnvironment

        /// How close to the tanning dose the engine plans. Setting it saves the
        /// profile: this selector is the profile, not a copy of it.
        @Published public var ceiling: Ceiling {
            didSet {
                guard ceiling != oldValue else { return }
                save { $0.ceiling = self.ceiling }
            }
        }

        /// The replayed state and the record it came from, as they stood at the
        /// last refresh. Published so the screen redraws when a write moves them.
        @Published public private(set) var state = DerivedState()
        @Published public private(set) var history = History()

        /// Weekly and cycle-to-date dose per region, as the store computed them
        /// at the last refresh (R24). Nothing here is stored: the store sums the
        /// logged record every time it is asked.
        @Published public private(set) var totals = Totals(week: [:], cycle: [:])

        public init(env: AppEnvironment) {
            self.env = env
            ceiling = env.profile.load()?.ceiling ?? AppEnvironment.startingProfile.ceiling
            Task { await refresh() }
        }

        /// Read the state and the record again. Every write here does this, and
        /// so does the screen when it appears.
        public func refresh() async {
            let now = env.clock()
            state = await (try? env.history.state(now: now)) ?? DerivedState()
            history = await (try? env.history.history()) ?? History()
            totals = await (try? env.history.totals(now: now)) ?? Totals(week: [:], cycle: [:])
        }

        // MARK: - What the screen says

        /// Whether the aggressive scale is available: enough reports, and at
        /// least one of them bounded a region in the current cycle (R7). Asked
        /// of the aggressive ceiling itself, so the answer does not depend on
        /// what is selected now.
        public var aggressiveUnlocked: Bool {
            let stored = env.profile.load() ?? AppEnvironment.startingProfile
            let asked = Profile(
                skinType: stored.skinType, ceiling: .aggressive, manualMultiplier: stored.manualMultiplier
            )
            return !TanningGoal.effectiveScale(
                profile: asked, state: state, tunables: env.tunables
            ).aggressiveRefused
        }

        /// How many reports the aggressive scale waits for — the number the
        /// locked line names.
        public var aggressiveUnlockCount: Int {
            env.tunables.aggressiveUnlockReports
        }

        /// How close to the binding threshold each ceiling plans, as a whole
        /// percentage — the number that names the option on the selector, since
        /// no approved copy names one.
        public func scalePercent(_ ceiling: Ceiling) -> Int {
            Int((env.tunables.ceilingScale(ceiling) * 100).rounded())
        }

        /// The multiplier the user has forced, if any.
        public var manualMultiplier: Double? {
            env.profile.load()?.manualMultiplier
        }

        /// The learned sensitivity, in the owner's sentence (R21). A multiplier
        /// below one is a lower personal threshold, which is more sensitive than
        /// typical; above one is less. The two words are arguments, not copy:
        /// the sentence is the approved line and this only fills its holes.
        public var sensitivitySentence: String {
            let multiplier = state.multiplier
            let percent = Int((abs(1 - multiplier) * 100).rounded())
            return AppCopy.text(
                .sensitivitySentence,
                args: [
                    "percent": String(percent),
                    "direction": multiplier < 1 ? "more" : "less",
                    "count": String(state.totalReports),
                ]
            )
        }

        /// Days that hold a logged session and no skin report — the calibration
        /// the app never got to do (R20).
        public var unreportedDays: Int {
            let logged = Set(history.sessions.filter { $0.state == .logged }.map(\.day))
            return logged.subtracting(Set(history.reports.map(\.day))).count
        }

        // MARK: - Sensitivity

        /// Replace the learned multiplier, or clear the replacement. The learned
        /// value keeps moving underneath it (R21); the memoised state is dropped
        /// because the profile it was keyed by has changed.
        public func overrideMultiplier(_ multiplier: Double?) async {
            save { $0.manualMultiplier = multiplier }
            await env.history.invalidate()
            await refresh()
        }

        /// Back to the learned value.
        public func resetSensitivity() async {
            await overrideMultiplier(nil)
        }

        // MARK: - The record

        /// The whole record as a file the user can keep (R25).
        public func exportFile() async throws -> URL {
            let profile = env.profile.load() ?? AppEnvironment.startingProfile
            let data = try await ExportService.export(
                store: env.history, profile: profile, now: env.clock()
            )
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.exportName)
            try data.write(to: url, options: .atomic)
            return url
        }

        /// Read a file back. The store lands it whole or not at all; the profile
        /// the file carried is applied with it, because a record replayed under
        /// a different skin type is not the record that was exported.
        public func importFile(_ url: URL) async throws -> ImportSummary {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let summary = try await ExportService.import(Data(contentsOf: url), into: env.history)
            env.profile.save(summary.profile)
            await env.history.invalidate()
            ceiling = summary.profile.ceiling
            await refresh()
            return summary
        }

        /// Start over (R44). The history is the record, so this is what deletes
        /// the calibration, the tan state and today's budget with it.
        public func deleteHistory() async throws {
            try await env.history.deleteAll()
            await env.history.invalidate()
            await refresh()
        }

        // MARK: - Inside

        private static let exportName = "icarus-history.json"

        /// Change the stored profile in place, starting from the app's own
        /// prior when onboarding has not saved one yet.
        private func save(_ change: (inout Profile) -> Void) {
            var profile = env.profile.load()
                ?? Profile(skinType: AppEnvironment.startingProfile.skinType, ceiling: ceiling)
            change(&profile)
            env.profile.save(profile)
        }
    }
#endif
