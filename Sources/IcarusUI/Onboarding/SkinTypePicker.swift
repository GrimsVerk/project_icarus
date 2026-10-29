#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI

    /// The six rows of the onboarding skin-type table, to pick from (R28).
    ///
    /// Every word on this screen is table data: each row shows its name and the
    /// plain description the user recognises themselves in, straight from
    /// `SkinTypeTable`, which is the app's own approved copy (R42). The chosen
    /// row is marked with a checkmark rather than with a word.
    ///
    /// The page is headed ONB-5 with ONB-6 under it. A user who cannot place
    /// themselves takes the questionnaire (ONB-7); once it has scored, the
    /// type it points to is marked and QUIZ-3 says the user may still pick
    /// another.
    public struct SkinTypePicker: View {
        @ObservedObject private var model: OnboardingModel

        public init(model: OnboardingModel) {
            self.model = model
        }

        public var body: some View {
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            QuizView(model: model)
                        } label: {
                            Label(AppCopy.text(.onboardingTakeQuiz), systemImage: "questionmark.circle")
                        }
                        if let suggested = model.quizSuggestion {
                            Text(AppCopy.text(.quizResult, args: ["type": CopyWords.roman(suggested)]))
                                .font(.footnote)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppCopy.text(.onboardingSkinTypeHeading))
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                            Text(AppCopy.text(.onboardingSkinTypeIntro))
                                .font(.subheadline)
                        }
                        .textCase(nil)
                    }
                    Section {
                        ForEach(SkinTypeTable.rows, id: \.type) { row in
                            typeRow(row)
                        }
                    }
                }
            }
        }

        private func typeRow(_ row: SkinTypeRow) -> some View {
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
            .accessibilityIdentifier("skinType.\(row.type.rawValue)")
        }
    }
#endif
