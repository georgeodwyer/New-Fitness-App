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
        launch(["-seed-sample", "-seed-history", "-simulate-gps", "120"] + (dark ? ["-dark"] : []))
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        snap("20-dashboard-1")
        for index in 2...6 {
            app.swipeUp()
            snap("20-dashboard-\(index)")
        }
        if !dark { skipOrSwap() }

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

        if !dark {
            strengthWorkout()
            runWorkout()
        }

        app.tabBars.buttons["Progress"].tap()
        snap("24-progress")
        let lift = app.buttons.matching(identifier: "progress.lift").firstMatch
        if lift.waitForExistence(timeout: 3) {
            lift.tap()
            snap("24b-exercise-history")
            app.navigationBars.buttons.firstMatch.tap()
        }

        app.tabBars.buttons["Settings"].tap()
        snap("25-settings")
        if app.buttons["settings.coaching"].firstMatch.waitForExistence(timeout: 3) {
            app.buttons["settings.coaching"].firstMatch.tap()
            snap("25b-audio-coaching")
            app.navigationBars.buttons.firstMatch.tap()
        }
        if app.buttons["settings.training"].firstMatch.waitForExistence(timeout: 3) {
            app.buttons["settings.training"].firstMatch.tap()
            snap("25c-training-profile")
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.swipeUp()
        snap("25d-settings-account")
        app.swipeUp()
        tap("Design system")
        _ = app.navigationBars["Design system"].waitForExistence(timeout: 5)
        snap("26-design-system")
        app.swipeUp()
        snap("27-design-system-2")
        app.swipeUp()
        snap("28-design-system-3")
    }

    /// Opens the skip/swap sheet for today's first session and swaps it.
    private func skipOrSwap() {
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        let button = app.buttons["Skip or swap"].firstMatch
        guard button.waitForExistence(timeout: 3) else { return }
        button.tap()
        snap("29-skip-or-swap")
        let option = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Low-impact cardio' OR label CONTAINS 'Reduced-volume'")).firstMatch
        if option.waitForExistence(timeout: 3) {
            option.tap()
            snap("29b-plan-updated")
        } else {
            app.swipeDown()
        }
    }

    /// Opens a run from the Plan tab and runs it with simulated GPS at 120× speed.
    private func runWorkout() {
        app.tabBars.buttons["Plan"].tap()
        let run = app.buttons.matching(NSPredicate(format: "identifier == 'plan.session' AND (label CONTAINS 'Run' OR label CONTAINS 'Intervals')")).firstMatch
        guard run.waitForExistence(timeout: 5) else { return }
        run.tap()
        tap("Start session")
        XCTAssertTrue(app.buttons["Start run"].waitForExistence(timeout: 10))
        snap("40-run-ready")
        tap("Start run")
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 10))
        sleep(9) // ~18 simulated minutes
        snap("41-run-live")
        sleep(5)
        snap("42-run-live-later")
        tap("Finish")
        tap("Finish run")
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        snap("43-run-effort")
        tap("Save")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        snap("44-run-summary")
        app.swipeUp()
        snap("45-run-summary-splits")
        app.swipeUp()
        snap("46-run-summary-efforts")
        tap("Done")
        if app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    /// Opens a strength session from the Plan tab, logs a set, and finishes.
    private func strengthWorkout() {
        app.tabBars.buttons["Plan"].tap()
        let strength = app.buttons.matching(NSPredicate(format: "identifier == 'plan.session' AND label CONTAINS 'Body'")).firstMatch
        guard strength.waitForExistence(timeout: 5) else { return }
        strength.tap()
        tap("Start session")
        XCTAssertTrue(app.buttons["Finish workout"].waitForExistence(timeout: 10))
        snap("30-strength-workout")
        let complete = app.buttons["Complete set 1"].firstMatch
        if complete.waitForExistence(timeout: 3) {
            complete.tap()
            snap("31-strength-rest-timer")
            if app.buttons["Skip"].exists { app.buttons["Skip"].tap() }
        }
        tap("Finish workout")
        XCTAssertTrue(app.buttons["Save workout"].waitForExistence(timeout: 5))
        snap("32-strength-finish")
        tap("Save workout")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        snap("33-strength-summary")
        tap("Done")
        // Back to the plan's session detail.
        if app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }
}
