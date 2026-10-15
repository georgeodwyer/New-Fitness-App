import XCTest
@testable import TrainingEngine

final class RouteTests: XCTestCase {
    private let origin = RouteCoordinate(latitude: 51.5073, longitude: -0.1657)

    private func at(north: Double, east: Double) -> RouteCoordinate {
        let (lat, lon) = Geo.offset(latitude: origin.latitude, longitude: origin.longitude, northMeters: north, eastMeters: east)
        return RouteCoordinate(latitude: lat, longitude: lon)
    }

    /// 500 m north, then 300 m east (a right turn), then 500 m south (another right turn).
    private var lShape: [RouteCoordinate] {
        stride(from: 0.0, through: 500, by: 50).map { at(north: $0, east: 0) }
            + stride(from: 50.0, through: 300, by: 50).map { at(north: 500, east: $0) }
            + stride(from: 450.0, through: 0, by: -50).map { at(north: $0, east: 300) }
    }

    func testLengthAndProjection() throws {
        let path = lShape
        XCTAssertEqual(RouteGeometry.length(path), 1300, accuracy: 2)
        let cumulative = RouteGeometry.cumulative(path)
        let projection = try XCTUnwrap(RouteGeometry.project(at(north: 200, east: 20), onto: path, cumulative: cumulative))
        XCTAssertEqual(projection.distanceFromRoute, 20, accuracy: 0.5)
        XCTAssertEqual(projection.alongMeters, 200, accuracy: 1)
        let midpoint = try XCTUnwrap(RouteGeometry.point(along: 650, path: path, cumulative: cumulative))
        XCTAssertEqual(midpoint.distance(to: at(north: 500, east: 150)), 0, accuracy: 1)
    }

    func testBearingAndTurns() {
        XCTAssertEqual(RouteGeometry.bearing(origin, at(north: 100, east: 0)), 0, accuracy: 0.5)
        XCTAssertEqual(RouteGeometry.bearing(origin, at(north: 0, east: 100)), 90, accuracy: 0.5)
        XCTAssertEqual(RouteGeometry.turnAngle(from: 350, to: 20), 30, accuracy: 0.001)
        XCTAssertEqual(RouteGeometry.turnAngle(from: 20, to: 350), -30, accuracy: 0.001)

        let turns = RouteGeometry.turnInstructions(lShape)
        XCTAssertEqual(turns.map(\.text), ["Turn right", "Turn right"])
        XCTAssertEqual(turns[0].distanceMeters, 500, accuracy: 2)
        XCTAssertEqual(turns[1].distanceMeters, 800, accuracy: 2)
    }

    func testSimplifyKeepsCorners() {
        let simple = RouteGeometry.simplify(lShape, tolerance: 5)
        XCTAssertEqual(simple.count, 4)
        XCTAssertEqual(simple[1].distance(to: at(north: 500, east: 0)), 0, accuracy: 1)
    }

    func testLoopGeneratorMakesALoopOfAboutTheRightSize() {
        let points = LoopGenerator.waypoints(start: origin, targetMeters: 5000, bearingDegrees: 45, roadFactor: 1)
        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(points.first, origin)
        XCTAssertEqual(points.last, origin)
        // A square inscribed in a circle of circumference 5 km: 4 × r√2 ≈ 4.5 km.
        XCTAssertEqual(RouteGeometry.length(points), 4502, accuracy: 30)
        // Heads off roughly the way asked (north-east quadrant).
        let bearing = RouteGeometry.bearing(origin, points[1])
        let first = bearing > 180 ? bearing - 360 : bearing
        XCTAssertTrue((-5...95).contains(first), "\(first)")

        XCTAssertEqual(LoopGenerator.adjustedRoadFactor(1.25, achievedMeters: 6000, targetMeters: 5000), 1.5, accuracy: 0.001)
        XCTAssertTrue(LoopGenerator.isCloseEnough(achievedMeters: 5400, targetMeters: 5000))
        XCTAssertFalse(LoopGenerator.isCloseEnough(achievedMeters: 5600, targetMeters: 5000))
    }

    func testGuideAnnouncesTurnsAndFinish() {
        let path = lShape
        let route = PlannedRoute(name: "L", waypoints: [path[0], path[path.count - 1]], path: path,
                                 instructions: RouteGeometry.turnInstructions(path), followsRoads: false)
        var guide = RouteGuide(route: route)
        var events: [RouteGuide.Event] = []
        // Run along the route every 10 m, 3 m to one side (GPS wobble).
        let cumulative = RouteGeometry.cumulative(path)
        for meters in stride(from: 0.0, through: 1300, by: 10) {
            let point = RouteGeometry.point(along: meters, path: path, cumulative: cumulative)!
            let (lat, lon) = Geo.offset(latitude: point.latitude, longitude: point.longitude, northMeters: 3, eastMeters: -3)
            events += guide.update(latitude: lat, longitude: lon)
        }
        XCTAssertEqual(events.filter { if case .upcoming = $0 { return true } else { return false } }.count, 2)
        XCTAssertEqual(events.filter { $0 == .now("Turn right") }.count, 2)
        XCTAssertFalse(events.contains(.offRoute))
        XCTAssertEqual(events.last, .finished)
        XCTAssertTrue(guide.isFinished)
        XCTAssertEqual(RouteGuide.Event.upcoming("Turn right onto Park Lane", inMeters: 104).announcement(units: .metric),
                       "In 100 metres, turn right onto Park Lane.")
    }

    func testGuideWarnsWhenOffRouteAndWhenBack() {
        let path = lShape
        let route = PlannedRoute(name: "L", waypoints: [], path: path, followsRoads: false)
        var guide = RouteGuide(route: route)
        var events: [RouteGuide.Event] = []
        for north in stride(from: 0.0, through: 200, by: 10) {
            events += guide.update(latitude: at(north: north, east: 0).latitude, longitude: at(north: north, east: 0).longitude)
        }
        // Wander 80 m west for a while.
        for north in stride(from: 200.0, through: 300, by: 10) {
            let point = at(north: north, east: -80)
            events += guide.update(latitude: point.latitude, longitude: point.longitude)
        }
        XCTAssertTrue(guide.isOffRoute)
        XCTAssertEqual(events.filter { $0 == .offRoute }.count, 1, "Warns once, not every fix")
        let back = at(north: 310, east: -5)
        events += guide.update(latitude: back.latitude, longitude: back.longitude)
        XCTAssertEqual(events.last, .backOnRoute)
        XCTAssertFalse(guide.isOffRoute)
        XCTAssertEqual(guide.alongMeters, 310, accuracy: 2)
    }

    func testGuideDoesNotJumpAheadOnAnOutAndBack() {
        // 1 km out and straight back along the same road.
        let out = stride(from: 0.0, through: 1000, by: 50).map { at(north: $0, east: 0) }
        let path = out + out.reversed().dropFirst()
        var guide = RouteGuide(route: PlannedRoute(name: "Out and back", waypoints: [], path: path, followsRoads: false))
        let cumulative = RouteGeometry.cumulative(path)
        for meters in stride(from: 0.0, through: 600, by: 10) {
            let point = RouteGeometry.point(along: meters, path: path, cumulative: cumulative)!
            _ = guide.update(latitude: point.latitude, longitude: point.longitude)
        }
        XCTAssertEqual(guide.alongMeters, 600, accuracy: 2, "Still on the way out, not matched to the way back")
        XCTAssertFalse(guide.isFinished)
    }

    func testGPXRoundTripAndImportFormats() {
        let path = lShape
        let text = GPXRoute.gpx(name: "Park & loop", path: path)
        let parsed = GPXRoute.parse(text)
        XCTAssertEqual(parsed.name, "Park & loop")
        XCTAssertEqual(parsed.points.count, path.count)
        XCTAssertEqual(parsed.points[5].distance(to: path[5]), 0, accuracy: 0.1)

        let routeFile = """
        <gpx><rte><name>Komoot route</name>
        <rtept lon='-0.1657' lat='51.5073'><ele>10</ele></rtept>
        <rtept lat="51.5083" lon="-0.1657"/>
        </rte></gpx>
        """
        let route = GPXRoute.parse(routeFile)
        XCTAssertEqual(route.name, "Komoot route")
        XCTAssertEqual(route.points, [RouteCoordinate(latitude: 51.5073, longitude: -0.1657),
                                      RouteCoordinate(latitude: 51.5083, longitude: -0.1657)])
        XCTAssertTrue(GPXRoute.parse("not a gpx file").points.isEmpty)
    }

    func testSimulatedRunnerFollowsAPath() {
        var runner = SimulatedRunner(structure: nil, driftMeters: 0)
        runner.path = lShape
        let samples = runner.samples(start: Date(timeIntervalSince1970: 0), duration: 120)
        let cumulative = RouteGeometry.cumulative(lShape)
        for sample in samples {
            let projection = RouteGeometry.project(RouteCoordinate(latitude: sample.latitude, longitude: sample.longitude),
                                                   onto: lShape, cumulative: cumulative)
            XCTAssertLessThan(projection?.distanceFromRoute ?? 999, 1)
        }
    }
}
