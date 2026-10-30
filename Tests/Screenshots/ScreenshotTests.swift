import XCTest

/// Walks the app on the preview environment (the recorded Oslo forecast, a
/// clock held at 2026-06-15 09:00 UTC, nothing on disk) and attaches a
/// screenshot of every main screen. It asserts only that each screen can be
/// reached; `.github/workflows/screenshots.yml` exports the attachments so the
/// owner can look at them.
///
/// Each test launches the app afresh, so no screen depends on how another test
/// left it.
final class ScreenshotTests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUp() {
        continueAfterFailure = false
    }

    func test01Onboarding() {
        let app = launch(preview: "fresh")
        let forward = app.buttons["onboarding.forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: timeout))
        snap("01-onboarding-1-module")

        forward.tap()
        let acknowledge = app.switches["disclaimer.acknowledge"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: timeout))
        snap("01-onboarding-2-disclaimer")
        // The switch is at the trailing end of a long label: tap the switch,
        // not the middle of the row.
        acknowledge.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()

        forward.tap()
        let typeIII = app.buttons["skinType.3"]
        XCTAssertTrue(typeIII.waitForExistence(timeout: timeout))
        typeIII.tap()
        snap("01-onboarding-3-skin-type")

        forward.tap()
        let finish = app.buttons["onboarding.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: timeout))
        snap("01-onboarding-4-permissions")

        finish.tap()
        XCTAssertTrue(app.buttons["calculator.compute"].waitForExistence(timeout: timeout))
        snap("02-calculator-after-onboarding")
    }

    func test02CalculatorResultAndTimer() {
        let app = launch(preview: "onboarded")
        let compute = app.buttons["calculator.compute"]
        XCTAssertTrue(compute.waitForExistence(timeout: timeout))
        snap("03-calculator")

        // Lying down, so the result offers the flip timer.
        app.buttons["calculator.posture"].tap()
        // CALC-5 in docs/APP_COPY.md: the menu's option is found by its words.
        let lying = app.buttons["Lying down, turning over"]
        XCTAssertTrue(lying.waitForExistence(timeout: timeout))
        lying.tap()
        compute.tap()

        let timer = app.buttons["result.timer"]
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: timeout))
        sleep(1)
        snap("04-result")
        app.swipeUp()
        snap("04-result-middle")
        // The actions close a long list, and a row off screen does not exist yet.
        XCTAssertTrue(scroll(app, to: timer))
        snap("04-result-scrolled")

        timer.tap()
        sleep(1)
        snap("05-flip-timer")

        // TIM-1 in docs/APP_COPY.md.
        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: timeout))
        start.tap()
        sleep(2)
        snap("05-flip-timer-running")
    }

    func test03History() {
        let empty = launch(preview: "onboarded")
        let opener = empty.buttons["history"]
        XCTAssertTrue(opener.waitForExistence(timeout: timeout))
        opener.tap()
        sleep(1)
        snap("06-history-empty")

        let app = launch(preview: "onboarded")
        let compute = app.buttons["calculator.compute"]
        XCTAssertTrue(compute.waitForExistence(timeout: timeout))
        compute.tap()
        // Log the planned session, so History has a row to show.
        let didThis = app.buttons["result.didThis"]
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: timeout))
        XCTAssertTrue(scroll(app, to: didThis))
        didThis.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let history = app.buttons["history"]
        XCTAssertTrue(history.waitForExistence(timeout: timeout))
        history.tap()
        sleep(1)
        snap("06-history")

        // A session that has ended, which is what the chart plots.
        let past = launch(preview: "yesterday")
        let pastHistory = past.buttons["history"]
        XCTAssertTrue(pastHistory.waitForExistence(timeout: timeout))
        pastHistory.tap()
        sleep(1)
        snap("06-history-past-session")
        sleep(5)
        snap("06-history-past-session-later")
    }

    func test04Settings() {
        let app = launch(preview: "onboarded")
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        settings.tap()
        sleep(1)
        snap("07-settings")
        app.swipeUp()
        snap("07-settings-scrolled")
    }

    func test05Learn() {
        let app = launch(preview: "onboarded")
        let learnTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(learnTab.waitForExistence(timeout: timeout))
        learnTab.tap()
        let first = app.buttons["learn.module.1"]
        XCTAssertTrue(first.waitForExistence(timeout: timeout))
        snap("08-learn-list")

        first.tap()
        sleep(1)
        snap("09-learn-module")
    }

    func test06SkinCheck() {
        // The day before the preview clock's day, as a tapped notification.
        _ = launch(preview: "onboarded", tapping: "skin-2026-06-14@Europe/Oslo")
        sleep(2)
        snap("10-skin-check")
    }

    func test07LastingColour() {
        _ = launch(preview: "onboarded", tapping: "colour-2026-06-11@Europe/Oslo")
        sleep(2)
        snap("11-lasting-colour")
    }

    /// The skin check's real questions: the preview logs a session the day
    /// before, with no report yet.
    func test08SkinCheckQuestions() {
        _ = launch(preview: "yesterday", tapping: "skin-2026-06-14@Europe/Oslo")
        sleep(2)
        snap("10-skin-check-questions")
    }

    /// The two sheets the Result opens: the place and the other SPF.
    func test09ResultSheets() {
        let app = launch(preview: "onboarded")
        let compute = app.buttons["calculator.compute"]
        XCTAssertTrue(compute.waitForExistence(timeout: timeout))
        compute.tap()

        // RES-4 and RES-7 in docs/APP_COPY.md.
        let place = app.buttons["Change place"]
        XCTAssertTrue(place.waitForExistence(timeout: timeout))
        place.tap()
        sleep(1)
        snap("12-sheet-change-place")
        app.swipeDown(velocity: .fast)
        sleep(1)

        let otherSPF = app.buttons["I don't have that SPF"]
        XCTAssertTrue(scroll(app, to: otherSPF))
        otherSPF.tap()
        sleep(1)
        snap("12-sheet-no-such-spf")
    }

    func test10Quiz() {
        let app = launch(preview: "fresh")
        let forward = app.buttons["onboarding.forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: timeout))
        forward.tap()
        let acknowledge = app.switches["disclaimer.acknowledge"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: timeout))
        acknowledge.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        forward.tap()

        // ONB-7 in docs/APP_COPY.md.
        let quiz = app.buttons["Take the questionnaire"]
        XCTAssertTrue(quiz.waitForExistence(timeout: timeout))
        quiz.tap()
        sleep(1)
        snap("13-quiz")
    }

    /// What the phone shows today: no WeatherKit, so no forecast.
    func test11NoForecast() {
        let app = launch(preview: "noforecast")
        let compute = app.buttons["calculator.compute"]
        XCTAssertTrue(compute.waitForExistence(timeout: timeout))
        compute.tap()
        sleep(2)
        snap("14-result-no-forecast")
    }

    func test12DarkMode() {
        // `XCUIDevice.shared.appearance` left the app light on the runner, so
        // the app takes the scheme from a launch argument instead.
        walkMainScreens(prefix: "15-dark", dark: true)
    }

    func test13LargestText() {
        let fresh = launch(preview: "fresh", textSize: Self.largestText)
        let forward = fresh.buttons["onboarding.forward"]
        XCTAssertTrue(forward.waitForExistence(timeout: timeout))
        forward.tap()
        sleep(1)
        snap("16-large-onboarding-disclaimer")
        walkMainScreens(prefix: "16-large", textSize: Self.largestText)
    }

    // MARK: - Inside

    /// The largest accessibility text size, as UIKit names it.
    private static let largestText = "UICTContentSizeCategoryAccessibilityXXXL"

    /// The Calculator, the Result top and bottom, and Settings top, middle and
    /// end, on the preview with a session the day before: the screens a
    /// dark-mode or text-size check needs (screen review F4).
    private func walkMainScreens(prefix: String, textSize: String? = nil, dark: Bool = false) {
        let app = launch(preview: "yesterday", textSize: textSize, dark: dark)
        // At the largest text sizes the plan button is pages down the list and
        // does not exist until it is scrolled to: wait for the bar instead.
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: timeout))
        sleep(1)
        snap("\(prefix)-calculator")
        let compute = app.buttons["calculator.compute"]
        XCTAssertTrue(scroll(app, to: compute))
        compute.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: timeout))
        sleep(1)
        snap("\(prefix)-result")
        app.swipeUp()
        app.swipeUp()
        snap("\(prefix)-result-scrolled")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: timeout))
        settings.tap()
        sleep(1)
        snap("\(prefix)-settings")
        app.swipeUp()
        snap("\(prefix)-settings-scrolled")
        app.swipeUp()
        snap("\(prefix)-settings-end")
    }

    private func launch(
        preview: String,
        tapping notification: String? = nil,
        textSize: String? = nil,
        dark: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-IcarusPreview", preview]
        if let notification {
            app.launchArguments += ["-IcarusTapNotification", notification]
        }
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        if dark {
            app.launchArguments += ["-IcarusAppearance", "dark"]
        }
        app.launch()
        return app
    }

    /// Swipes up until the element is on screen, a few times at most.
    private func scroll(_ app: XCUIApplication, to element: XCUIElement) -> Bool {
        for _ in 0 ..< 8 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
