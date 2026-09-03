#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// "Did you notice lasting colour?", days after the report it belongs to.
    ///
    /// One page and three answers, per day: yes, a little, no (R20). Answering
    /// writes the answer against that day's report and closes the flow, which is
    /// also what takes the row off the due card — the card re-reads what is due
    /// when the sheet dismisses.
    ///
    /// It shows the day it is about and no figure at all: no MED, no SED, no
    /// dose (R20, R39). It carries no banner.
    ///
    /// **A copy gap, deliberately not filled here.** `docs/APP_COPY.md` approves
    /// the notification's wording (`notificationLastingColour`), which is not a
    /// `CopyKey` yet, and nothing approves an in-app question line or words for
    /// the three answers. So the page shows the day as a date and the answers as
    /// their own case names, split into words — data the enum already carries,
    /// never a sentence written here (R42). The missing keys are a gap for the
    /// owner to close.
    public struct LastingColourFlow: View, ScreenManifest {
        public static let hasBannerSlot = false
        public static let showsFigures = false

        @ObservedObject private var model: LastingColourModel
        @Environment(\.dismiss) private var dismiss

        public init(model: LastingColourModel) {
            self.model = model
        }

        public var body: some View {
            List {
                Section {
                    Text(dayText)
                }
                Section {
                    ForEach(Self.answers, id: \.self) { option in
                        Button {
                            answer(option)
                        } label: {
                            row(PromptWords.words(option.rawValue), chosen: model.answered == option)
                        }
                    }
                }
            }
        }

        // MARK: - Answering

        /// Write the answer and leave. A write that fails — a day whose report
        /// is gone — leaves the page open with nothing recorded, because there
        /// is no approved line to explain the failure with.
        private func answer(_ option: LastingColour) {
            Task {
                try? await model.submit(option, now: model.env.clock())
                if model.answered != nil {
                    dismiss()
                }
            }
        }

        // MARK: - Inside

        private func row(_ words: String, chosen: Bool) -> some View {
            HStack {
                Text(words)
                Spacer()
                if chosen {
                    Image(systemName: "checkmark")
                }
            }
        }

        /// The day the question is about, as a date in that day's own zone.
        private var dayText: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.timeZone = TimeZone(identifier: model.day.timeZoneID) ?? .current
            return formatter.string(from: model.day.start())
        }

        /// The three answers, in the order R20 lists them. `LastingColour` is
        /// not `CaseIterable`, and the order is the design's rather than the
        /// declaration's.
        private static let answers: [LastingColour] = [.yes, .aLittle, .no]
    }
#endif
