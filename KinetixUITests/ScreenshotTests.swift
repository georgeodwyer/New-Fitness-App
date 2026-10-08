import XCTest

/// Walks through the app and saves a screenshot of each screen.
/// Screenshots are attached to the test results and, when the
/// SCREENSHOT_DIR environment variable is set (CI sets it), written as PNGs.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = ""

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = prefix + name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(prefix + name + ".png")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }

    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing button \(label)", file: file, line: line)
        button.tap()
    }

    private func next() { tap("Continue") }

    func testOnboardingFlow() {
        prefix = "light-"
        launch()
        snap("01-onboarding-units")
        next()
        tap("Intermediate"); snap("02-onboarding-running"); next()
        snap("03-onboarding-race-time"); tap("Skip")
        tap("Intermediate"); snap("04-onboarding-lifting"); next()
        snap("05-onboarding-lift-numbers"); tap("Skip")
        tap("Half marathon"); snap("06-onboarding-goal"); next()
        snap("07-onboarding-event"); tap("Skip")
        snap("08-onboarding-days"); next()
        snap("09-onboarding-doubles"); next()
        tap("Full gym"); snap("10-onboarding-equipment"); next()
        snap("11-onboarding-finish")
        tap("Build my plan")
        XCTAssertTrue(app.buttons["Start training"].waitForExistence(timeout: 10))
        snap("12-plan-preview-top")
        app.swipeUp()
        snap("13-plan-preview-zones")
        app.swipeUp()
        snap("14-plan-preview-first-week")
        tap("Start training")
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        snap("15-today")
    }

    func testMainScreensLight() { mainScreens(dark: false) }
    func testMainScreensDark() { mainScreens(dark: true) }

    private func mainScreens(dark: Bool) {
        prefix = dark ? "dark-" : "light-"
        launch(["-seed-sample"] + (dark ? ["-dark"] : []))
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        snap("20-today")

        app.tabBars.buttons["Plan"].tap()
        snap("21-plan")
        let session = app.buttons.matching(identifier: "plan.session").firstMatch
        if session.waitForExistence(timeout: 5) {
            session.tap()
            snap("22-session-detail")
            app.swipeUp()
            snap("23-session-detail-scrolled")
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.tabBars.buttons["Progress"].tap()
        snap("24-progress")

        app.tabBars.buttons["Settings"].tap()
        snap("25-settings")
        tap("Design system")
        snap("26-design-system")
        app.swipeUp()
        snap("27-design-system-2")
        app.swipeUp()
        snap("28-design-system-3")
    }
}
