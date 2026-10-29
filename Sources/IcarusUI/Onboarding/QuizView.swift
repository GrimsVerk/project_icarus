#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import SwiftUI

    /// The optional Fitzpatrick questionnaire (R28).
    ///
    /// Ten questions, each a picker over its own answers; questions, answers and
    /// points are all `FitzpatrickQuiz` data and none of them is written here.
    /// The answers are kept as question id → option index rather than as points,
    /// so two answers worth the same score stay distinguishable and the picker
    /// shows the one the user actually chose.
    ///
    /// Answering updates `quizScore` as it goes; nothing changes the chosen skin
    /// type until the confirm button runs `applyQuiz()`, which is what sends the
    /// user back to the table with that type marked.
    public struct QuizView: View {
        @ObservedObject private var model: OnboardingModel
        @Environment(\.dismiss) private var dismiss
        /// Question id → the index of the chosen option.
        @State private var answers: [Int: Int] = [:]

        public init(model: OnboardingModel) {
            self.model = model
        }

        public var body: some View {
            Form {
                ForEach(FitzpatrickQuiz.questions, id: \.id) { question in
                    Picker(selection: binding(for: question)) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { offset, option in
                            Text(option.text).tag(Optional(offset))
                        }
                    } label: {
                        Text(question.text)
                    }
                }
            }
            .navigationTitle(AppCopy.text(.quizTitle))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.applyQuiz()
                        dismiss()
                    } label: {
                        Text(AppCopy.text(.quizDone))
                    }
                    .disabled(model.quizScore == nil)
                }
            }
        }

        /// The selection of one question's picker. The setter scores the whole
        /// questionnaire from the answers as they will be after this change,
        /// rather than reading the state back mid-update.
        private func binding(for question: QuizQuestion) -> Binding<Int?> {
            Binding(
                get: { answers[question.id] },
                set: { chosen in
                    var updated = answers
                    updated[question.id] = chosen
                    answers = updated
                    model.quizScore = Self.score(of: updated)
                }
            )
        }

        /// The total of the answered questions. An unanswered question scores
        /// nothing, which is the same as its most sensitive answer — the score
        /// only means something once every question has been answered, and the
        /// user is the one who decides that by confirming.
        private static func score(of answers: [Int: Int]) -> Int {
            FitzpatrickQuiz.questions.reduce(0) { total, question in
                guard let index = answers[question.id], question.options.indices.contains(index) else {
                    return total
                }
                return total + question.options[index].points
            }
        }
    }
#endif
