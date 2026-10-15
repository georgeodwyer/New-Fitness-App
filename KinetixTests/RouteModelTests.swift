import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class RouteModelTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    private var sampleRoute: PlannedRoute {
        let start = RouteCoordinate(latitude: 51.5073, longitude: -0.1657)
        let points = LoopGenerator.waypoints(start: start, targetMeters: 3000, bearingDegrees: 90, roadFactor: 1)
        return PlannedRoute(name: "Park loop", waypoints: points, path: points,
                            instructions: RouteGeometry.turnInstructions(points), followsRoads: false)
    }

    func testRouteStoresAndSyncs() throws {
        let context = try makeContext()
        let route = sampleRoute
        let model = RouteModel(route: route)
        context.insert(model)
        try context.save()
        XCTAssertEqual(model.route, route)
        XCTAssertEqual(model.distanceMeters, route.distanceMeters, accuracy: 0.01)

        let record = try model.syncRecord()
        XCTAssertEqual(record.type, "route")
        let copy = RouteModel.makeForSync(id: model.id)
        try copy.apply(record, context: context)
        XCTAssertEqual(copy.route, route)
    }

    func testImportedRouteGetsDirectionsFromItsShape() throws {
        let gpx = GPXRoute.gpx(name: "Imported", path: sampleRoute.path)
        let parsed = GPXRoute.parse(gpx)
        let route = RouteService.imported(name: parsed.name ?? "", points: parsed.points)
        XCTAssertEqual(route.name, "Imported")
        XCTAssertFalse(route.followsRoads)
        XCTAssertTrue(route.isLoop)
        XCTAssertFalse(route.instructions.isEmpty)
        let file = try RouteService.gpxFile(for: route)
        XCTAssertEqual(file.pathExtension, "gpx")
        XCTAssertEqual(GPXRoute.parse(try String(contentsOf: file, encoding: .utf8)).points.count, route.path.count)
    }

    func testStraightLineRouteNeedsNoNetwork() async throws {
        let points = sampleRoute.waypoints
        let result = await RouteService.build(name: "Straight", waypoints: points, followRoads: false)
        XCTAssertTrue(result.allRouted)
        XCTAssertEqual(result.route.path, points)
        XCTAssertEqual(result.route.distanceMeters, RouteGeometry.length(points), accuracy: 0.01)
    }

    func testRunFollowingARouteShowsProgress() throws {
        let context = try makeContext()
        let model = RunWorkoutModel(planned: nil, custom: CustomRunWorkout.starter(for: .free, zones: nil), route: sampleRoute,
                                    units: .metric, settings: nil, simulationSpeed: 10, context: context)
        let status = try XCTUnwrap(model.routeStatus)
        XCTAssertEqual(status.remainingMeters, (sampleRoute.distanceMeters / 10).rounded() * 10, accuracy: 0.01)
        XCTAssertFalse(status.isOffRoute)
        XCTAssertNotNil(status.nextDirection)

        let noRoute = RunWorkoutModel(planned: nil, custom: nil, units: .metric, settings: nil, simulationSpeed: 10, context: context)
        XCTAssertNil(noRoute.routeStatus)
    }
}
