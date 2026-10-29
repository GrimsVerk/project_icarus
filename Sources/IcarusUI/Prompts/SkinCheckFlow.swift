#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// The day-after skin check, in the order R20 asks it: the sessions that
    /// were never accounted for, then how the skin looks, then when the colour
    /// showed up, then which region, then anything unusual — and the one line
    /// that says what the answer did.
    ///
    /// A day with nothing logged is a dead end on purpose: there is no dose for
    /// the report to be evidence about, so the flow says so and records nothing
    /// (D-2026-09-03-T4).
    ///
    /// No figure appears anywhere in it, and no MED or SED (R20, R39). It
    /// carries no banner.
    public struct SkinCheckFlow: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = false

        @ObservedObject private var model: SkinCheckModel
        @State private var page: Page = .sessions
        @State private var confirmation: Confirmation?

        public init(model: SkinCheckModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                List {
                    switch page {
                    case .sessions: sessions
                    case .nothingLogged: nothingLogged
                    case .look: look
                    case .timing: timing
                    case .region: region
                    case .confounders: confounders
                    case .confirmation: confirmed
                    }
                }
                .navigationTitle(AppCopy.text(.skinCheckTitle))
            }
            .task {
                await model.load()
                advanceFromSessions()
            }
        }

        private enum Page {
            case sessions
            case nothingLogged
            case look
            case timing
            case region
            case confounders
            case confirmation
        }

        /// The line the flow ends on: the key the effect chose and the values
        /// that key's placeholders take.
        private struct Confirmation {
            let key: CopyKey
            let args: [String: String]
        }

        // MARK: - Did you do this session?

        /// One question per still-planned session. Answering removes it from
        /// the list, so the page empties itself and then moves on.
        private var sessions: some View {
            ForEach(model.planned) { record in
                DidYouDoThisView(
                    record: record,
                    zone: zone,
                    skinType: skinType,
                    ladder: model.env.tunables.spfLadder,
                    onYes: { intervals, wore in
                        Task {
                            try? await model.didDo(record.id, actual: intervals, wore: wore)
                            advanceFromSessions()
                        }
                    },
                    onNo: {
                        Task {
                            try? await model.didNotDo(record.id)
                            advanceFromSessions()
                        }
                    }
                )
            }
        }

        private var nothingLogged: some View {
            Text(AppCopy.text(.noSessionToReport, skinType: skinType))
        }

        // MARK: - Q1 and Q2

        /// How does your skin look today? (SKIN-2), and R21's five answers
        /// (SKIN-3 to SKIN-7).
        private var look: some View {
            Section {
                ForEach(SkinAnswer.allCases, id: \.self) { option in
                    Button {
                        model.answer = option
                        page = option == .normal ? .region : .timing
                        if option == .normal {
                            model.timing = nil
                        }
                    } label: {
                        row(CopyWords.answer(option), chosen: model.answer == option)
                    }
                }
            } header: {
                heading(.skinQuestionLook)
            }
        }

        /// When did it show up? Asked only after an answer that named redness,
        /// and required before that report can be submitted.
        private var timing: some View {
            Section {
                ForEach(Self.timings, id: \.self) { option in
                    Button {
                        model.timing = option
                        page = .region
                    } label: {
                        row(CopyWords.timing(option), chosen: model.timing == option)
                    }
                }
            } header: {
                heading(.skinQuestionTiming)
            }
        }

        // MARK: - Region and confounders

        /// Which region the answer is about. "All exposed" is the default and
        /// the first row, because it is the honest answer most of the time.
        private var region: some View {
            Section {
                ForEach(Self.regions, id: \.self) { option in
                    Button {
                        model.region = option
                        page = .confounders
                    } label: {
                        row(CopyWords.reportRegion(option), chosen: model.region == option)
                    }
                }
            } header: {
                heading(.skinQuestionRegion)
            }
        }

        /// Anything unusual? Any number of them, including none, and then the
        /// report is written.
        private var confounders: some View {
            Section {
                ForEach(Confounder.allCases, id: \.self) { option in
                    Button {
                        if model.confounders.contains(option) {
                            model.confounders.remove(option)
                        } else {
                            model.confounders.insert(option)
                        }
                    } label: {
                        row(CopyWords.confounder(option), chosen: model.confounders.contains(option))
                    }
                }
                Button(action: submit) {
                    Label(AppCopy.text(.skinSendReport), systemImage: "checkmark.circle")
                }
                .disabled(!model.canSubmit)
            } header: {
                heading(.skinQuestionConfounders)
            }
        }

        // MARK: - The confirmation

        @ViewBuilder
        private var confirmed: some View {
            if let confirmation {
                Text(AppCopy.text(confirmation.key, skinType: skinType, args: confirmation.args))
            }
        }

        /// Write the report and show the line for what it did. A day that
        /// already has a report is the one failure with its own words: the
        /// store refuses the second one and nothing is written.
        private func submit() {
            Task {
                do {
                    let effect = try await model.submit(now: model.env.clock())
                    confirmation = Confirmation(
                        key: SkinCheckModel.confirmationKey(for: effect),
                        args: SkinCheckModel.confirmationArgs(for: effect)
                    )
                } catch {
                    guard let failure = error as? HistoryError, case .alreadyReported = failure else { return }
                    confirmation = Confirmation(key: .alreadyReported, args: [:])
                }
                page = .confirmation
            }
        }

        // MARK: - Inside

        /// The sessions page is done when nothing is still planned: the day
        /// then either has something logged to be evidence about, or it does
        /// not and there is nothing to report at all.
        private func advanceFromSessions() {
            guard page == .sessions, model.planned.isEmpty else { return }
            page = model.hasLoggedSession ? .look : .nothingLogged
        }

        private func row(_ words: String, chosen: Bool) -> some View {
            HStack {
                Text(words)
                Spacer()
                if chosen {
                    Image(systemName: "checkmark")
                }
            }
        }

        /// A question above its answers, in the owner's own case: a section
        /// header would otherwise shout it in capitals.
        private func heading(_ key: CopyKey) -> some View {
            Text(AppCopy.text(key, skinType: skinType))
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)
        }

        private var zone: TimeZone {
            TimeZone(identifier: model.day.timeZoneID) ?? .current
        }

        private var skinType: SkinType {
            model.env.profile.load()?.skinType ?? AppEnvironment.startingProfile.skinType
        }

        /// The four timings and the four regions, in the order R20 lists them.
        /// Neither enum is `CaseIterable`, and the order is the design's rather
        /// than the declaration's.
        private static let timings: [RednessTiming] = [
            .withinHourGoneByEvening, .thatEvening, .nextMorning, .notSure,
        ]

        private static let regions: [ReportRegion] = [.allExposed, .front, .back, .headAndShoulders]
    }
#endif
