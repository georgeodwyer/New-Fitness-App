import Foundation
import MapKit
import SwiftData
import TrainingEngine

/// Turns the points tapped on the map into a route that follows roads and paths (Apple Maps
/// walking directions, free and built in), or straight lines between them, plus the
/// directions to speak. Also builds loops of a chosen distance.
@MainActor
enum RouteService {
    struct Leg {
        var path: [RouteCoordinate]
        /// Directions with distances measured from the start of this leg.
        var instructions: [RouteInstruction]
        /// False when Apple Maps couldn't find a way (straight line instead).
        var routed: Bool
    }

    /// Recently worked-out legs, so undo and re-adding a point don't ask Apple Maps again.
    private static var cache: [String: Leg] = [:]

    static func leg(from a: RouteCoordinate, to b: RouteCoordinate, followRoads: Bool) async -> Leg {
        let straight = Leg(path: [a, b], instructions: [], routed: !followRoads)
        guard followRoads, a.distance(to: b) > 5 else { return straight }
        let key = "\(a.latitude),\(a.longitude)>\(b.latitude),\(b.longitude)"
        if let cached = cache[key] { return cached }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)))
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return Leg(path: [a, b], instructions: [], routed: false) }

        var points = route.polyline.coordinateList.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        // Join exactly at the tapped points so legs connect.
        if points.first.map({ $0.distance(to: a) > 1 }) ?? true { points.insert(a, at: 0) }
        if points.last.map({ $0.distance(to: b) > 1 }) ?? true { points.append(b) }

        var instructions: [RouteInstruction] = []
        var along = 0.0
        for (index, step) in route.steps.enumerated() {
            let text = step.instructions.trimmingCharacters(in: .whitespaces)
            // The first step is "Start on …" and the last "The destination is on your left";
            // neither helps mid-run (the start of each leg is just a point you tapped).
            let isArrival = index == route.steps.count - 1 && step.distance < 1
            if index > 0, !text.isEmpty, !isArrival {
                instructions.append(RouteInstruction(distanceMeters: along, text: text))
            }
            along += step.distance
        }
        let leg = Leg(path: points, instructions: instructions, routed: true)
        cache[key] = leg
        return leg
    }

    /// The full route through the waypoints, in order.
    static func build(name: String, waypoints: [RouteCoordinate], followRoads: Bool, id: UUID = UUID()) async -> (route: PlannedRoute, allRouted: Bool) {
        guard let first = waypoints.first else {
            return (PlannedRoute(id: id, name: name, waypoints: [], path: [], followsRoads: followRoads), true)
        }
        var path = [first]
        var instructions: [RouteInstruction] = []
        var allRouted = true
        for (a, b) in zip(waypoints, waypoints.dropFirst()) {
            let leg = await leg(from: a, to: b, followRoads: followRoads)
            let offset = RouteGeometry.length(path)
            instructions += leg.instructions.map { RouteInstruction(distanceMeters: $0.distanceMeters + offset, text: $0.text) }
            path += leg.path.dropFirst()
            allRouted = allRouted && leg.routed
        }
        if !followRoads || !allRouted {
            // No street directions (or only some): work them out from the line's shape.
            instructions = followRoads ? mergedInstructions(instructions, RouteGeometry.turnInstructions(path))
                                       : RouteGeometry.turnInstructions(path)
        }
        return (PlannedRoute(id: id, name: name, waypoints: waypoints, path: path, instructions: instructions,
                             followsRoads: followRoads), allRouted)
    }

    /// A loop of about `targetMeters` from `start`. Tries up to three sizes to get within 10%.
    static func loop(name: String, start: RouteCoordinate, targetMeters: Double, bearingDegrees: Double,
                     followRoads: Bool) async -> PlannedRoute {
        var factor = followRoads ? 1.3 : 1.0
        var best: PlannedRoute?
        for _ in 0..<3 {
            let waypoints = LoopGenerator.waypoints(start: start, targetMeters: targetMeters, bearingDegrees: bearingDegrees,
                                                    roadFactor: factor)
            let route = await build(name: name, waypoints: waypoints, followRoads: followRoads).route
            if best.map({ abs($0.distanceMeters - targetMeters) > abs(route.distanceMeters - targetMeters) }) ?? true {
                best = route
            }
            if LoopGenerator.isCloseEnough(achievedMeters: route.distanceMeters, targetMeters: targetMeters) { break }
            factor = LoopGenerator.adjustedRoadFactor(factor, achievedMeters: route.distanceMeters, targetMeters: targetMeters)
        }
        return best ?? PlannedRoute(name: name, waypoints: [start], path: [start], followsRoads: followRoads)
    }

    /// A route from an imported GPX file: its line as-is, with directions from its shape.
    static func imported(name: String, points: [RouteCoordinate]) -> PlannedRoute {
        let path = RouteGeometry.simplify(points, tolerance: 2)
        let waypoints = RouteGeometry.simplify(points, tolerance: 60)
        return PlannedRoute(name: name, waypoints: waypoints, path: path,
                            instructions: RouteGeometry.turnInstructions(path), followsRoads: false)
    }

    /// Writes a route as a .gpx file for sharing.
    nonisolated static func gpxFile(for route: PlannedRoute) throws -> URL {
        let safeName = route.name.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safeName.isEmpty ? "Route" : safeName).gpx")
        try GPXRoute.gpx(name: route.name, path: route.path).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func mergedInstructions(_ a: [RouteInstruction], _ b: [RouteInstruction]) -> [RouteInstruction] {
        var result = a
        for instruction in b where !a.contains(where: { abs($0.distanceMeters - instruction.distanceMeters) < 30 }) {
            result.append(instruction)
        }
        return result.sorted { $0.distanceMeters < $1.distanceMeters }
    }
}

extension MKPolyline {
    var coordinateList: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

extension RouteCoordinate {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
