#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI

    /// "Did you do this session?" for one still-planned session, and everything
    /// that follows a "yes" (R20).
    ///
    /// Yes asks what was worn — the prescribed pair, another product, or none —
    /// and then offers the planned times to correct before the session is
    /// logged. No discards the session and asks nothing else. A session with no
    /// prescription does not offer "as prescribed" at all, because there is no
    /// pair for it to mean.
    public struct DidYouDoThisView: View {
        private let record: SessionRecord
        private let zone: TimeZone
        private let skinType: SkinType
        private let ladder: [Int]
        private let onYes: ([ExposureInterval], SunscreenConfirmation) -> Void
        private let onNo: () -> Void

        @State private var page: Page = .didYouDoIt
        @State private var intervals: [ExposureInterval]
        @State private var wore: SunscreenConfirmation = .none
        @State private var label: Int
        @State private var application: Application = .normal

        public init(
            record: SessionRecord,
            zone: TimeZone,
            skinType: SkinType,
            ladder: [Int],
            onYes: @escaping ([ExposureInterval], SunscreenConfirmation) -> Void,
            onNo: @escaping () -> Void
        ) {
            self.record = record
            self.zone = zone
            self.skinType = skinType
            self.ladder = ladder.sorted()
            self.onYes = onYes
            self.onNo = onNo
            _intervals = State(initialValue: record.plannedIntervals)
            _label = State(initialValue: record.prescribedSunscreen?.spfLabel ?? ladder.sorted().first ?? 0)
            _wore = State(initialValue: record.prescribedSunscreen == nil ? .none : .asPrescribed)
        }

        public var body: some View {
            List {
                switch page {
                case .didYouDoIt: askedIt
                case .wore: askedWore
                case .times: askedTimes
                }
            }
        }

        private enum Page {
            case didYouDoIt
            case wore
            case times
        }

        // MARK: - The question

        private var askedIt: some View {
            Section {
                Text(AppCopy.text(.didYouDoThisSession, skinType: skinType, args: [
                    "window": ResultCopy.windowText(record.plannedWindow, in: zone),
                ]))
                Button { page = record.prescribedSunscreen == nil ? .times : .wore } label: {
                    Image(systemName: "checkmark.circle")
                }
                Button(action: onNo) {
                    Image(systemName: "xmark.circle")
                }
            }
        }

        // MARK: - Did you wear it?

        /// The prescribed pair is named by the approved line; the other two
        /// answers are the enum's own words, because no copy key names them.
        private var askedWore: some View {
            Section {
                if let prescribed = record.prescribedSunscreen {
                    Text(AppCopy.text(.didYouWearIt, skinType: skinType, args: [
                        "spf": "SPF \(prescribed.spfLabel)",
                        "application": prescribed.application.rawValue,
                    ]))
                    choiceRow(.asPrescribed, words: PromptWords.words(SunscreenWord.asPrescribed.rawValue))
                }
                choiceRow(.alternative(alternative), words: PromptWords.words(SunscreenWord.another.rawValue))
                if case .alternative = wore {
                    labelPicker
                    applicationPicker
                }
                choiceRow(.none, words: PromptWords.words(SunscreenWord.none.rawValue))
                Button { page = .times } label: {
                    Image(systemName: "chevron.forward")
                }
            }
        }

        /// The three answers, each a row that marks itself when it is the one
        /// chosen. An alternative is compared by its case and not by its pair,
        /// so changing the SPF underneath keeps the row selected.
        private func choiceRow(_ choice: SunscreenConfirmation, words: String) -> some View {
            Button { wore = choice } label: {
                HStack {
                    Text(words)
                    Spacer()
                    if same(choice, wore) {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        private var labelPicker: some View {
            Picker(selection: labelBinding) {
                ForEach(ladder, id: \.self) { spf in
                    Text(String(spf)).tag(spf)
                }
            } label: {
                Image(systemName: "drop.circle")
            }
        }

        private var applicationPicker: some View {
            Picker(selection: applicationBinding) {
                ForEach(Application.allCases, id: \.self) { applied in
                    Text(PromptWords.words(applied.rawValue)).tag(applied)
                }
            } label: {
                Image(systemName: "hand.draw")
            }
        }

        // MARK: - The times

        private var askedTimes: some View {
            Section {
                IntervalEditor(intervals: $intervals)
                Button { onYes(intervals, wore) } label: {
                    Image(systemName: "checkmark.circle")
                }
            }
        }

        // MARK: - Inside

        private var alternative: SunscreenChoice {
            SunscreenChoice(spfLabel: label, application: application)
        }

        /// Picking an SPF or an application is itself the answer "another
        /// product": the two pickers are only shown once that row is chosen, and
        /// they keep it chosen.
        private var labelBinding: Binding<Int> {
            Binding(get: { label }, set: { label = $0; wore = .alternative(alternative) })
        }

        private var applicationBinding: Binding<Application> {
            Binding(get: { application }, set: { application = $0; wore = .alternative(alternative) })
        }

        private func same(_ one: SunscreenConfirmation, _ other: SunscreenConfirmation) -> Bool {
            switch (one, other) {
            case (.asPrescribed, .asPrescribed), (.none, .none), (.alternative, .alternative): true
            default: false
            }
        }

        /// The three answers as words. They are cases of an enum rather than
        /// strings at the call site, so the flow holds no sentence of its own.
        private enum SunscreenWord: String {
            case asPrescribed
            case another
            case none
        }
    }
#endif
