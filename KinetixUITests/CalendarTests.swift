import XCTest

/// Opens the calendar from Today's "This week" tile and from the Plan tab, flicks through
/// months and checks the app is still running. Runs on every CI build.
final class CalendarTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample", "-seed-history"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        return app
    }

    func testCalendarFromToday() { openFromToday(launch([])) }
    func testCalendarFromTodayLongPlan() { openFromToday(launch(["-seed-weeks", "40"])) }

    private func openFromToday(_ app: XCUIApplication) {
        let tile = app.descendants(matching: .any).matching(identifier: "today.weekTile").firstMatch
        for _ in 0..<6 where !(tile.exists && tile.isHittable) { app.swipeUp() }
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "No This week tile")
        tile.tap()
        checkCalendar(app)
    }

    func testCalendarFromPlan() {
        let app = launch([])
        app.tabBars.buttons["Plan"].tap()
        let button = app.buttons["Calendar"].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
            checkCalendar(app)
        }
    }

    private func checkCalendar(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 15), "Calendar didn't open")
        // Give the preview weeks time to arrive.
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "App stopped after opening the calendar")
        let next = app.buttons["Next month"].firstMatch
        for _ in 0..<4 where next.exists { next.tap() }
        let previous = app.buttons["Previous month"].firstMatch
        for _ in 0..<6 where previous.exists { previous.tap() }
        let race = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Race'")).firstMatch
        if race.exists { race.tap() }
        app.navigationBars["Calendar"].buttons["Today"].tap()
        XCTAssertEqual(app.state, .runningForeground, "App stopped while using the calendar")
        app.navigationBars["Calendar"].buttons["Done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10), "Calendar didn't close")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
