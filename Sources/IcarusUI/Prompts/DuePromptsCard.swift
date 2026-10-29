#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// The questions that are due right now, in the app.
    ///
    /// This is the fallback R20 requires for a notification that was never
    /// allowed or was never answered: the scheduler decides what is due from the
    /// history and the clock, and this only shows the rows and opens the flow
    /// behind one. It is also where a notification whose identifier means
    /// nothing lands, so a tap always reaches a real question or an empty card
    /// rather than the wrong day.
    ///
    /// It shows no figure and carries no banner (R39).
    public struct DuePromptsCard: View {
        private let env: AppEnvironment
        @State private var due: [DuePrompt] = []
        @State private var open: OpenPrompt?

        public init(env: AppEnvironment) {
            self.env = env
        }

        /// A stack rather than a `List`: above the Calculator's form a list
        /// takes half the screen even with nothing in it, and this card has to
        /// take no room at all on a day with nothing due.
        public var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(due.map(OpenPrompt.init)) { prompt in
                    Button { open = prompt } label: {
                        Text(words(for: prompt.prompt))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    Divider()
                }
            }
            .task { await reload() }
            .sheet(
                item: $open,
                onDismiss: { Task { await reload() } },
                content: { prompt in flow(for: prompt.prompt) }
            )
        }

        /// Read what is due. Every write the flows make invalidates the store's
        /// memo, so re-reading after one closes is what takes an answered
        /// question off the card.
        public func reload() async {
            guard let history = try? await env.history.history() else {
                due = []
                return
            }
            due = await env.prompts.dueInApp(history: history, now: env.clock())
        }

        // MARK: - Inside

        /// A due prompt with an identity, so it can be the sheet's item. Two
        /// prompts are never the same day and kind twice, so the day's own
        /// identifier is the identity.
        private struct OpenPrompt: Identifiable {
            let prompt: DuePrompt

            var id: String {
                switch prompt {
                case let .skinCheck(day): "skin-" + day.id
                case let .lastingColour(day): "colour-" + day.id
                }
            }
        }

        @ViewBuilder
        private func flow(for prompt: DuePrompt) -> some View {
            switch prompt {
            case let .skinCheck(day):
                SkinCheckFlow(model: SkinCheckModel(env: env, day: day, channel: .inApp))
            case let .lastingColour(day):
                LastingColourFlow(model: LastingColourModel(env: env, day: day, channel: .inApp))
            }
        }

        /// The row's words: the question it opens, which is the approved copy
        /// for the skin check. The lasting-colour question's own line arrives
        /// with its flow.
        private func words(for prompt: DuePrompt) -> String {
            switch prompt {
            case .skinCheck:
                AppCopy.text(.didYouDoThisSession, skinType: skinType, args: ["window": ""])
            case let .lastingColour(day):
                dayText(day)
            }
        }

        /// A day as a date, in its own zone. No copy key names the
        /// lasting-colour row, so it shows the day it is about and nothing
        /// else, until its own flow brings its line (Slice 2).
        private func dayText(_ day: DayKey) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.timeZone = TimeZone(identifier: day.timeZoneID) ?? .current
            return formatter.string(from: day.start())
        }

        private var skinType: SkinType {
            env.profile.load()?.skinType ?? AppEnvironment.startingProfile.skinType
        }
    }
#endif
