#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import SwiftUI

    /// The six rows of the onboarding skin-type table, to pick from (R28).
    ///
    /// Every word on this screen is table data: each row shows its name and the
    /// plain description the user recognises themselves in, straight from
    /// `SkinTypeTable`, which is the app's own approved copy (R42). The chosen
    /// row is marked with a checkmark rather than with a word.
    ///
    /// A user who cannot place themselves reaches the questionnaire from the
    /// toolbar. No approved copy names that affordance, so it is the
    /// `questionmark.circle` symbol alone, and what VoiceOver reads for it is
    /// the quiz's first question — data, not a sentence written here (R35).
    public struct SkinTypePicker: View {
        @ObservedObject private var model: OnboardingModel

        public init(model: OnboardingModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                List(SkinTypeTable.rows, id: \.type) { row in
                    Button {
                        model.skinType = row.type
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                Text(row.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if model.skinType == row.type {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            QuizView(model: model)
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel(Text(quizLabel))
                    }
                }
            }
        }

        /// The quiz's first question, which is what the questionnaire asks and
        /// so the closest thing to a name for it that the approved content has.
        private var quizLabel: String {
            FitzpatrickQuiz.questions.first?.text ?? ""
        }
    }
#endif
