#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    /// Slice 2 of `calculator-ui`, asserted without rendering a view.
    ///
    /// The flow's completion rule is the thing the slice promises is testable,
    /// so it is asserted on `OnboardingModel` — the model is the subject here
    /// and nothing about it is faked. The real boundary underneath it is the
    /// profile store, and that is a `MemoryProfileStore` (or the one
    /// `AppEnvironment.preview()` composes): nothing touches the disk, the
    /// network, or the wall clock.
    ///
    /// Nothing renders. `OnboardingFlow`, `SkinTypePicker`, `QuizView` and
    /// `DisclaimerView` need a host application to build, and every promise the
    /// slice makes is reachable without one.
    @MainActor
    final class OnboardingModelTests: XCTestCase {
        // MARK: - Fixtures

        /// A first launch: nothing saved, no flags set.
        private func firstLaunchStore() -> MemoryProfileStore {
            MemoryProfileStore(profile: nil)
        }

        private func makeModel() -> OnboardingModel {
            OnboardingModel(store: firstLaunchStore())
        }

        /// The published band boundaries, restated from R28 rather than read
        /// from the questionnaire, so a change to the bands shows up as a
        /// disagreement instead of moving both sides at once.
        private static let bands: [(score: Int, type: SkinType)] = [
            (0, .i), (6, .i),
            (7, .ii), (12, .ii),
            (13, .iii), (18, .iii),
            (19, .iv), (24, .iv),
            (25, .v), (30, .v),
            (31, .vi), (40, .vi),
        ]

        // MARK: - Nothing is answered until the user answers it

        func testANewModelHasAnsweredNothing() {
            let model = makeModel()

            XCTAssertFalse(model.disclaimerAcknowledged)
            XCTAssertNil(model.skinType)
            XCTAssertNil(model.quizScore)
            XCTAssertFalse(model.canComplete, "a first launch cannot already be complete")
        }

        /// Both answers are required, and neither one alone is enough.
        func testAcknowledgingTheDisclaimerAloneDoesNotCompleteTheFlow() {
            let model = makeModel()

            model.disclaimerAcknowledged = true

            XCTAssertFalse(model.canComplete, "a profile with no skin type must not be savable")
        }

        func testChoosingASkinTypeAloneDoesNotCompleteTheFlow() {
            let model = makeModel()

            model.skinType = .iii

            XCTAssertFalse(model.canComplete, "the disclaimer is not optional (R29)")
        }

        func testTheFlowCompletesOnceBothAnswersAreIn() {
            let model = makeModel()

            model.disclaimerAcknowledged = true
            model.skinType = .iii

            XCTAssertTrue(model.canComplete)
        }

        /// `canComplete` is the current answer, not a latch: taking either
        /// answer back makes the flow incomplete again.
        func testTakingBackEitherAnswerMakesTheFlowIncompleteAgain() {
            let model = makeModel()
            model.disclaimerAcknowledged = true
            model.skinType = .iii

            model.skinType = nil
            XCTAssertFalse(model.canComplete)

            model.skinType = .iii
            model.disclaimerAcknowledged = false
            XCTAssertFalse(model.canComplete)
        }

        /// The picker offers the six rows of the onboarding table (R28), so
        /// every one of them has to be a complete answer.
        func testEveryRowOfTheSkinTypeTableCompletesTheFlow() {
            XCTAssertEqual(SkinTypeTable.rows.count, 6, "the table is types I...VI")

            for row in SkinTypeTable.rows {
                let model = makeModel()
                model.disclaimerAcknowledged = true
                model.skinType = row.type

                XCTAssertTrue(model.canComplete, "type \(row.type.rawValue) is not completable")
                XCTAssertEqual(model.complete().skinType, row.type)
            }
        }

        // MARK: - The optional quiz

        func testTheLowestQuizScoreChoosesTypeOne() {
            let model = makeModel()

            model.quizScore = 0
            model.applyQuiz()

            XCTAssertEqual(model.skinType, .i)
        }

        func testAQuizScoreAboveTheTopBandChoosesTypeSix() {
            let model = makeModel()

            model.quizScore = 40
            model.applyQuiz()

            XCTAssertEqual(model.skinType, .vi)
        }

        /// The table names the type the questionnaire pointed to (QUIZ-3), and
        /// a row picked afterwards still wins.
        func testTheQuizSuggestionIsNamedAndARowPickedAfterItWins() {
            let model = makeModel()
            XCTAssertNil(model.quizSuggestion)

            model.quizScore = 15
            model.applyQuiz()
            XCTAssertEqual(model.quizSuggestion, .iii)

            model.skinType = .iv
            XCTAssertEqual(model.skinType, .iv)
            XCTAssertEqual(model.quizSuggestion, .iii)
        }

        /// The mapping is the questionnaire's, not the model's own: every band
        /// boundary lands where `FitzpatrickQuiz` says it lands.
        func testEveryBandBoundaryIsMappedThroughTheQuestionnaire() {
            for band in Self.bands {
                let model = makeModel()
                model.quizScore = band.score

                model.applyQuiz()

                XCTAssertEqual(model.skinType, band.type, "score \(band.score)")
                XCTAssertEqual(
                    model.skinType,
                    FitzpatrickQuiz.skinType(forScore: band.score),
                    "score \(band.score) did not go through FitzpatrickQuiz"
                )
            }
        }

        /// The quiz is one way to answer the skin-type question, so answering
        /// it is enough to finish the flow.
        func testAnsweringTheQuizCompletesTheFlow() {
            let model = makeModel()
            model.disclaimerAcknowledged = true

            model.quizScore = 20
            model.applyQuiz()

            XCTAssertEqual(model.skinType, .iv)
            XCTAssertTrue(model.canComplete)
        }

        /// The quiz is optional: applying it with nothing answered must not
        /// invent a skin type, and must not overwrite one already chosen.
        func testApplyingAnUnansweredQuizChangesNothing() {
            let untouched = makeModel()
            untouched.applyQuiz()
            XCTAssertNil(untouched.skinType, "an unanswered quiz chose a type anyway")
            XCTAssertFalse(untouched.canComplete)

            let chosen = makeModel()
            chosen.skinType = .iv
            chosen.applyQuiz()
            XCTAssertEqual(chosen.skinType, .iv, "an unanswered quiz overwrote the user's own answer")
        }

        /// Taking the quiz after guessing replaces the guess — that is what it
        /// is for.
        func testAnsweringTheQuizReplacesAnEarlierGuess() {
            let model = makeModel()
            model.skinType = .vi

            model.quizScore = 3
            model.applyQuiz()

            XCTAssertEqual(model.skinType, .i)
        }

        /// The quiz answers the skin-type question and nothing else.
        func testTheQuizNeverAcknowledgesTheDisclaimer() {
            let model = makeModel()

            model.quizScore = 10
            model.applyQuiz()

            XCTAssertFalse(model.disclaimerAcknowledged, "the quiz acknowledged the disclaimer for the user")
        }

        // MARK: - What completing writes

        func testCompletingSavesTheProfileTheUserChose() {
            let store = firstLaunchStore()
            let model = OnboardingModel(store: store)
            model.disclaimerAcknowledged = true
            model.skinType = .ii

            let profile = model.complete()

            XCTAssertEqual(profile, Profile(skinType: .ii, ceiling: .standard, manualMultiplier: nil))
            XCTAssertEqual(store.load(), profile, "the profile was not saved")
        }

        /// A new user plans at the standard ceiling with no override: the
        /// aggressive setting is earned later (R23) and the manual multiplier is
        /// a Settings escape hatch, not an onboarding answer.
        func testCompletingSavesTheStandardCeilingAndNoManualMultiplier() {
            let store = firstLaunchStore()
            let model = OnboardingModel(store: store)
            model.disclaimerAcknowledged = true
            model.skinType = .v

            let profile = model.complete()

            XCTAssertEqual(profile.ceiling, .standard)
            XCTAssertNil(profile.manualMultiplier)
            XCTAssertEqual(store.load()?.ceiling, .standard)
            XCTAssertNil(store.load()?.manualMultiplier)
        }

        /// The two flags are what stops the app asking again on the next
        /// launch, and the acknowledgement has to outlive the model.
        func testCompletingSetsTheOnboardingAndDisclaimerFlags() {
            let store = firstLaunchStore()
            XCTAssertFalse(store.flags().onboardingComplete)
            XCTAssertFalse(store.flags().disclaimerAcknowledged)
            let model = OnboardingModel(store: store)
            model.disclaimerAcknowledged = true
            model.skinType = .i

            _ = model.complete()

            XCTAssertTrue(store.flags().onboardingComplete, "the app will ask again on the next launch")
            XCTAssertTrue(store.flags().disclaimerAcknowledged)
        }

        // MARK: - The whole flow, on the preview environment

        /// First launch on the environment the previews and the UI tests run
        /// on: nothing saved, no flags, nothing completable.
        func testThePreviewEnvironmentIsAFirstLaunch() {
            let environment = AppEnvironment.preview()

            XCTAssertNil(environment.profile.load())
            XCTAssertFalse(environment.profile.flags().onboardingComplete)
            XCTAssertFalse(OnboardingModel(store: environment.profile).canComplete)
        }

        /// Module 1, the disclaimer, the quiz, then the permissions page: what
        /// the user is left with is a saved profile and both flags set.
        func testTheQuizPathEndsWithASavedProfileAndBothFlags() {
            let environment = AppEnvironment.preview()
            let model = OnboardingModel(store: environment.profile)

            model.disclaimerAcknowledged = true
            model.quizScore = 27
            model.applyQuiz()
            XCTAssertTrue(model.canComplete)
            let profile = model.complete()

            XCTAssertEqual(profile.skinType, .v)
            XCTAssertEqual(environment.profile.load(), profile)
            XCTAssertTrue(environment.profile.flags().onboardingComplete)
            XCTAssertTrue(environment.profile.flags().disclaimerAcknowledged)
        }

        // MARK: - The first page is Module 1, unsoftened (R28)

        /// The flow opens on the Learn module itself, not on a retelling of
        /// it: the text the first page carries is module 1's own markdown.
        func testTheFirstPageCarriesModuleOnesOwnText() throws {
            let id = try XCTUnwrap(ModuleID(1))
            let module = try XCTUnwrap(ModuleIndex.module(id))

            XCTAssertEqual(OnboardingModel.module1.id, id)
            XCTAssertEqual(OnboardingModel.module1.markdown, module.markdown)
            XCTAssertEqual(OnboardingModel.module1, module)
        }

        /// R28's "there is no safe tan" framing reaches the first page whole.
        /// Softening it is the one edit this page must never make (V5, S9).
        func testTheFirstPageKeepsTheUnsoftenedFraming() {
            let text = OnboardingModel.module1.markdown

            XCTAssertTrue(text.hasPrefix("## Module 1 — "), "the first page is not module 1")
            XCTAssertTrue(text.contains("It cannot make tanning safe."))
            XCTAssertTrue(text.contains("there is no way to build a tan without doing some damage first"))
        }
    }

    /// The onboarding flow's slot declaration, checked against the table S15
    /// reads. No banner over a first launch, and no figure the user could act
    /// on (R39, R40).
    final class OnboardingScreenTests: XCTestCase {
        func testTheOnboardingFlowDeclaresNeitherSlot() {
            XCTAssertFalse(OnboardingFlow.hasBannerSlot)
            XCTAssertFalse(OnboardingFlow.showsFigures)
        }

        func testTheOnboardingFlowAgreesWithItsRowInTheTable() throws {
            let row = try XCTUnwrap(ScreenTable.row("OnboardingFlow"))

            XCTAssertEqual(row.hasBanner, OnboardingFlow.hasBannerSlot)
            XCTAssertEqual(row.showsFigures, OnboardingFlow.showsFigures)
            XCTAssertFalse(row.hasBanner)
            XCTAssertFalse(row.showsFigures)
        }
    }
#endif
