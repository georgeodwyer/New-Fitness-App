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
        let notice = app.buttons["onboarding.healthNotice"]
        if !notice.isHittable { app.swipeUp() }
        notice.tap()
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
        let bell = app.buttons["Plan updates"].firstMatch
        if bell.waitForExistence(timeout: 3) {
            bell.tap()
            snap("20b-plan-updates")
            if app.buttons["Done"].waitForExistence(timeout: 3) { app.buttons["Done"].tap() }
        }
        for index in 2...6 {
            app.swipeUp()
            snap("20-dashboard-\(index)")
        }
        if !dark { skipOrSwap() }

        app.tabBars.buttons["Plan"].tap()
        snap("21-plan")
        let allChanges = app.buttons["plan.allChanges"].firstMatch
        for _ in 0..<4 where !allChanges.exists { app.swipeUp() }
        if allChanges.waitForExistence(timeout: 3) {
            allChanges.tap()
            snap("21b-what-changed")
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
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
            recordRun()
        }

        app.tabBars.buttons["Progress"].tap()
        if app.buttons["Running"].waitForExistence(timeout: 3) { app.buttons["Running"].tap() }
        snap("24-progress-running")
        app.swipeUp()
        snap("24a-progress-running-2")
        let run = app.buttons.matching(identifier: "progress.run").firstMatch
        if run.waitForExistence(timeout: 3) {
            run.tap()
            snap("24c-run-detail")
            app.swipeUp()
            snap("24d-run-detail-charts")
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        if app.buttons["Strength"].waitForExistence(timeout: 3) { app.buttons["Strength"].tap() }
        snap("24e-progress-strength")
        let session = app.buttons.matching(identifier: "progress.strengthSession").firstMatch
        for _ in 0..<3 where !session.exists { app.swipeUp() }
        if session.waitForExistence(timeout: 3) {
            session.tap()
            snap("24f-strength-session-detail")
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let lift = app.buttons.matching(identifier: "progress.lift").firstMatch
        if lift.waitForExistence(timeout: 3) {
            lift.tap()
            snap("24b-exercise-history")
            app.navigationBars.buttons.firstMatch.tap()
        }
        if app.buttons["Overall"].waitForExistence(timeout: 3) { app.buttons["Overall"].tap() }
        snap("24g-progress-overall")

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
        for (identifier, name) in [("settings.health", "25e-apple-health"), ("settings.heartRate", "25f-heart-rate-strap"), ("settings.strava", "25g-strava")] {
            let row = app.buttons[identifier].firstMatch
            if !row.exists { app.swipeUp() }
            guard row.waitForExistence(timeout: 3) else { continue }
            row.tap()
            snap(name)
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.swipeUp()
        snap("25d-settings-account")
        let privacy = app.buttons["Privacy policy"].firstMatch
        if !privacy.exists { app.swipeUp() }
        if privacy.waitForExistence(timeout: 3) {
            privacy.tap()
            snap("25h-privacy")
            app.navigationBars.buttons.firstMatch.tap()
        }
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

    /// Record tab: builds a tempo run, saves it as a template and opens the run screen.
    private func recordRun() {
        app.tabBars.buttons["Record"].tap()
        snap("50-record")
        let run = app.buttons["record.run"].firstMatch
        guard run.waitForExistence(timeout: 5) else { return }
        run.tap()
        let tempo = app.buttons["record.type.tempo"].firstMatch
        if tempo.waitForExistence(timeout: 5) { tempo.tap() }
        snap("51-record-run-setup")
        let edit = app.buttons["record.editWorkout"].firstMatch
        if edit.waitForExistence(timeout: 3) {
            edit.tap()
            snap("52-record-workout-builder")
            let effort = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Effort'")).firstMatch
            if effort.waitForExistence(timeout: 3) {
                effort.tap()
                snap("53-record-step-editor")
                if app.buttons["Done"].waitForExistence(timeout: 3) { app.buttons["Done"].tap() }
            }
            app.navigationBars.buttons.firstMatch.tap()
        }
        let save = app.buttons["record.saveTemplate"].firstMatch
        if save.waitForExistence(timeout: 3) { save.tap() }
        app.buttons["record.startRun"].firstMatch.tap()
        let extra = app.buttons["No, it's an extra run"]
        if extra.waitForExistence(timeout: 3) {
            snap("54-record-planned-question")
            extra.tap()
        }
        XCTAssertTrue(app.buttons["Start run"].waitForExistence(timeout: 10))
        snap("55-record-run-ready")
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
        if app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        snap("56-record-with-template")
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
