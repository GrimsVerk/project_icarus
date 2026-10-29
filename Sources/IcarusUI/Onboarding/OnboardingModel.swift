#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData

    /// What onboarding knows, and the one rule that decides when it is done.
    ///
    /// The pages are views; the rule is here, so it can be asserted without
    /// rendering anything. Two answers are required and neither has a default:
    /// the disclaimer must be acknowledged (R29) and a skin type must be chosen
    /// (R28). The optional quiz never chooses on its own — it produces a score,
    /// and `applyQuiz()` is what turns that score into the choice, so the user
    /// still sees the type they end up with in the table.
    @MainActor
    public final class OnboardingModel: ObservableObject {
        /// The module first launch shows, unsoftened (R28).
        ///
        /// It is the Learn text itself and not a retelling of it: the flow
        /// renders this module with the same `ModuleView` the Learn tab uses.
        public static let module1: LearnModule = {
            guard let id = ModuleID(1), let module = ModuleIndex.module(id) else {
                preconditionFailure("Module 1 is missing from the Learn index")
            }
            return module
        }()

        @Published public var disclaimerAcknowledged = false
        @Published public var skinType: SkinType?
        /// The quiz total, once the user has answered anything. Nil means the
        /// quiz was never opened, or nothing in it was answered.
        @Published public var quizScore: Int?
        /// The type the last confirmed questionnaire pointed to, which the
        /// table page names (QUIZ-3). The user may still pick another row.
        @Published public private(set) var quizSuggestion: SkinType?

        private let store: any ProfileStore

        public init(store: any ProfileStore) {
            self.store = store
        }

        /// True once both required answers are in. The flow's last page is what
        /// reads this; nothing is saved before it is true.
        public var canComplete: Bool {
            disclaimerAcknowledged && skinType != nil
        }

        /// Turns the quiz total into the skin type, through the published
        /// scoring bands (R28). With no score there is nothing to apply, and the
        /// choice the user may already have made in the table is left alone.
        public func applyQuiz() {
            guard let score = quizScore else { return }
            let suggested = FitzpatrickQuiz.skinType(forScore: score)
            skinType = suggested
            quizSuggestion = suggested
        }

        /// Saves the profile and the flags, and hands the profile back.
        ///
        /// The ceiling starts at `.standard`: the conservative setting is what
        /// the engine falls back to before calibration anyway, and aggressive is
        /// locked until there is history to unlock it with. The multiplier is
        /// nil, because nothing has been learned yet and an override is the
        /// Settings screen's to set.
        ///
        /// Calling this while `canComplete` is false is a programmer error, not
        /// a user one: the flow does not offer the button.
        public func complete() -> Profile {
            precondition(canComplete, "onboarding completed before the disclaimer and the skin type were answered")
            guard let skinType else {
                preconditionFailure("canComplete is true with no skin type")
            }
            let profile = Profile(skinType: skinType, ceiling: .standard, manualMultiplier: nil)
            store.save(profile)
            var flags = store.flags()
            flags.onboardingComplete = true
            flags.disclaimerAcknowledged = true
            store.setFlags(flags)
            return profile
        }
    }
#endif
