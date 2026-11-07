import XCTest

/// Workout → Functional → Build a functional workout: opens the builder, adds stations and
/// saves. Runs on every CI build (it once crashed on opening).
final class FunctionalUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBuildAFunctionalWorkout() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-seed-sample"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Workout"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Workout"].tap()

        let card = app.descendants(matching: .any).matching(identifier: "record.functional").firstMatch
        for _ in 0..<4 where !(card.exists && card.isHittable) { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 5), "No Functional card")
        card.tap()

        let build = app.descendants(matching: .any).matching(identifier: "functional.build").firstMatch
        for _ in 0..<4 where !(build.exists && build.isHittable) { app.swipeUp() }
        XCTAssertTrue(build.waitForExistence(timeout: 5), "No Build button")
        build.tap()
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "App stopped opening the builder")

        let name = app.textFields["functional.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Builder didn't open")
        name.tap()
        name.typeText("CI circuit")

        let add = app.buttons["functional.addStation"].firstMatch
        for _ in 0..<4 where !(add.exists && add.isHittable) { app.swipeUp() }
        add.tap()
        let run = app.buttons["Run"].firstMatch
        if run.waitForExistence(timeout: 3) { run.tap() }
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground, "App stopped adding a station")

        app.buttons["functional.save"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground, "App stopped saving")
    }
}
