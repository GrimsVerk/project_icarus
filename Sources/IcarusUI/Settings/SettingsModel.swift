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
        /// profile: this selector is the profile, not a copy of it. A locked
        /// aggressive is refused and the choice stays where it was, so picking
        /// it can never strand the selector (R7, screen review F6).
        @Published public var ceiling: Ceiling {
            didSet {
                guard ceiling != oldValue, !settingStored else { return }
                guard isSelectable(ceiling) else {
                    setStored(oldValue)
                    return
                }
                save { $0.ceiling = self.ceiling }
            }
        }

        /// True while the selector is set to what the profile already holds,
        /// which is neither a pick to check nor a change to save.
        private var settingStored = false

        /// The replayed state and the record it came from, as they stood at the
        /// last refresh. Published so the screen redraws when a write moves them.
        @Published public private(set) var state = DerivedState()
        @Published public private(set) var history = History()

        /// Weekly and cycle-to-date dose per region, as the store computed them
        /// at the last refresh (R24). Nothing here is stored: the store sums the
        /// logged record every time it is asked.
        @Published public private(set) var totals = Totals(week: [:], cycle: [:])

        /// Apple's weather attribution, once WeatherKit has given it (R29).
        @Published public private(set) var attribution: WeatherAttribution?

        /// Whether the ad network's privacy options are offered (R39): only
        /// where its consent form applies.
        @Published public private(set) var privacyOptionsRequired = false

        /// The file the user picked, waiting for them to accept the warning
        /// that an import replaces everything (HIST-4). Picking never imports.
        @Published public private(set) var pendingImport: URL?

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
            privacyOptionsRequired = env.ads.privacyOptionsRequired
            attribution = await env.weatherAttribution()
        }

        /// The owner's privacy policy page (R41).
        public var privacyPolicyURL: URL? {
            env.privacyPolicyURL
        }

        /// Opens the ad network's privacy options form, where a user changes
        /// their consent answer.
        public func showPrivacyOptions() async {
            await env.ads.presentPrivacyOptions()
            privacyOptionsRequired = env.ads.privacyOptionsRequired
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

        /// Whether the selector offers this ceiling now: every one but a
        /// locked aggressive.
        public func isSelectable(_ ceiling: Ceiling) -> Bool {
            ceiling != .aggressive || aggressiveUnlocked
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

        /// The skin type the app plans for: the profile's, or the starting
        /// prior before onboarding saved one.
        public var skinType: SkinType {
            env.profile.load()?.skinType ?? AppEnvironment.startingProfile.skinType
        }

        /// The learned sensitivity, in the owner's sentence (R21). A multiplier
        /// below one is a lower personal threshold, which is more sensitive than
        /// typical; above one is less. The two words are arguments, not copy:
        /// the sentence is the approved line and this only fills its holes.
        /// Before any report there is nothing learned to put in it (SET-7).
        public var sensitivitySentence: String {
            guard state.totalReports > 0 else { return AppCopy.text(.sensitivityNoReports) }
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

        /// The unreported days as a sentence, or that there are none (SET-11).
        public var unreportedSentence: String {
            let count = unreportedDays
            guard count > 0 else { return AppCopy.text(.unreportedNone) }
            return AppCopy.text(.unreportedDays, args: ["count": String(count)])
        }

        // MARK: - Skin type

        /// Change the skin type the app plans for: where `revisitSkinType`
        /// sends the user (SET-21). The ceiling and any override stay as they
        /// were; the replay is dropped, because the prior it started from has
        /// changed.
        public func setSkinType(_ type: SkinType) async {
            let stored = env.profile.load()
                ?? Profile(skinType: AppEnvironment.startingProfile.skinType, ceiling: ceiling)
            let changed = Profile(skinType: type, ceiling: stored.ceiling, manualMultiplier: stored.manualMultiplier)
            env.profile.save(changed)
            await env.history.invalidate()
            await refresh()
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
            // The file's ceiling is the record's, not a pick: it is applied
            // as saved.
            setStored(summary.profile.ceiling)
            await refresh()
            return summary
        }

        /// Hold a picked file until the warning is answered.
        public func choose(_ url: URL) {
            pendingImport = url
        }

        /// The warning was refused: nothing is imported.
        public func cancelImport() {
            pendingImport = nil
        }

        /// The warning was accepted: import the file that was picked. With no
        /// file waiting there is nothing to do.
        public func confirmImport() async throws -> ImportSummary? {
            guard let url = pendingImport else { return nil }
            pendingImport = nil
            return try await importFile(url)
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

        /// Show a ceiling without checking or saving it.
        private func setStored(_ stored: Ceiling) {
            settingStored = true
            ceiling = stored
            settingStored = false
        }

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
