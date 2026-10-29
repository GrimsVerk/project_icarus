#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// "Did you notice lasting colour?", days after the report it belongs to.
    ///
    /// One page and three answers, per day: yes, a little, no (R20). Answering
    /// writes the answer against that day's report and says so (LC-4). The
    /// user swipes the sheet away, as at the end of the skin check, and the
    /// due card re-reads what is due when it dismisses.
    ///
    /// It shows the question for the day it is about (LC-2) and no figure at
    /// all: no MED, no SED, no dose (R20, R39). It carries no banner.
    public struct LastingColourFlow: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = false

        @ObservedObject private var model: LastingColourModel

        public init(model: LastingColourModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        Text(AppCopy.text(.lastingColourQuestion, args: ["day": dayText]))
                    }
                    Section {
                        ForEach(Self.answers, id: \.self) { option in
                            Button {
                                answer(option)
                            } label: {
                                row(CopyWords.lastingColour(option), chosen: model.answered == option)
                            }
                        }
                    }
                    if model.answered != nil {
                        Section {
                            Text(AppCopy.text(.lastingSaved))
                        }
                    }
                }
                .navigationTitle(AppCopy.text(.lastingColourTitle))
            }
        }

        // MARK: - Answering

        /// Write the answer; the page then says it is saved (LC-4) and the
        /// user swipes it away. A write that fails — a day whose report is gone
        /// — leaves the page as it was, with nothing recorded and nothing said,
        /// because there is no approved line to explain the failure with.
        private func answer(_ option: LastingColour) {
            Task {
                try? await model.submit(option, now: model.env.clock())
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
