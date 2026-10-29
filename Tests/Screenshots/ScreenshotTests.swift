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
        let lying = app.buttons["lyingTurning"]
        XCTAssertTrue(lying.waitForExistence(timeout: timeout))
        lying.tap()
        compute.tap()

        let timer = app.buttons["result.timer"]
        _ = timer.waitForExistence(timeout: timeout)
        snap("04-result")
        XCTAssertTrue(timer.exists)
        app.swipeUp()
        snap("04-result-scrolled")

        timer.tap()
        sleep(1)
        snap("05-flip-timer")
    }

    func test03History() {
        let app = launch(preview: "onboarded")
        let compute = app.buttons["calculator.compute"]
        XCTAssertTrue(compute.waitForExistence(timeout: timeout))
        compute.tap()
        // Log the planned session, so History has a row to show.
        let didThis = app.buttons["result.didThis"]
        _ = didThis.waitForExistence(timeout: timeout)
        snap("06-history-0-result")
        XCTAssertTrue(didThis.exists)
        didThis.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let history = app.buttons["history"]
        XCTAssertTrue(history.waitForExistence(timeout: timeout))
        history.tap()
        sleep(1)
        snap("06-history")
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

    // MARK: - Inside

    private func launch(preview: String, tapping notification: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-IcarusPreview", preview]
        if let notification {
            app.launchArguments += ["-IcarusTapNotification", notification]
        }
        app.launch()
        return app
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
