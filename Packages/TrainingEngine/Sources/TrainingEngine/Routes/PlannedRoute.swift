import Foundation

/// A latitude/longitude pair (degrees).
public struct RouteCoordinate: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public func distance(to other: RouteCoordinate) -> Double {
        Geo.distance(latitude, longitude, other.latitude, other.longitude)
    }
}

/// A spoken direction that applies at a point along the route ("Turn left onto Park Lane").
public struct RouteInstruction: Codable, Equatable, Sendable {
    /// Metres from the start of the route.
    public var distanceMeters: Double
    public var text: String

    public init(distanceMeters: Double, text: String) {
        self.distanceMeters = distanceMeters
        self.text = text
    }
}

/// A route planned on the map (or imported from GPX) to follow during a run.
public struct PlannedRoute: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The points the runner tapped (the line between them comes from `path`).
    public var waypoints: [RouteCoordinate]
    /// The full line to follow.
    public var path: [RouteCoordinate]
    public var instructions: [RouteInstruction]
    /// True when the line follows roads and paths; false for straight lines between taps.
    public var followsRoads: Bool

    public init(id: UUID = UUID(), name: String, waypoints: [RouteCoordinate], path: [RouteCoordinate],
                instructions: [RouteInstruction] = [], followsRoads: Bool = true) {
        self.id = id
        self.name = name
        self.waypoints = waypoints
        self.path = path
        self.instructions = instructions
        self.followsRoads = followsRoads
    }

    public var distanceMeters: Double { RouteGeometry.length(path) }

    /// Ends within 60 m of where it starts.
    public var isLoop: Bool {
        guard let first = path.first, let last = path.last, path.count > 2 else { return false }
        return first.distance(to: last) <= 60
    }
}

// MARK: - Geometry

public enum RouteGeometry {
    public static func length(_ path: [RouteCoordinate]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Distance from the start to each point.
    public static func cumulative(_ path: [RouteCoordinate]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(path.count)
        var total = 0.0
        for (index, point) in path.enumerated() {
            if index > 0 { total += path[index - 1].distance(to: point) }
            result.append(total)
        }
        return result
    }

    /// Compass bearing from `a` to `b` in degrees (0 = north, 90 = east).
    public static func bearing(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Double {
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Turn from one bearing to another, in -180...180 (positive = right).
    public static func turnAngle(from incoming: Double, to outgoing: Double) -> Double {
        var delta = (outgoing - incoming).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// Where a point sits relative to the route.
    public struct Projection: Equatable, Sendable {
        /// Metres from the point to the nearest part of the route.
        public var distanceFromRoute: Double
        /// Metres along the route of that nearest part.
        public var alongMeters: Double
    }

    /// The nearest point on the route, optionally only on segments that start within `alongRange`.
    public static func project(_ point: RouteCoordinate, onto path: [RouteCoordinate], cumulative: [Double],
                               alongRange: ClosedRange<Double>? = nil) -> Projection? {
        guard path.count > 1 else {
            return path.first.map { Projection(distanceFromRoute: point.distance(to: $0), alongMeters: 0) }
        }
        // Flat x/y metres around the point (accurate over a few km).
        let metersPerDegreeLat = Geo.earthRadius * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * cos(point.latitude * .pi / 180)
        func xy(_ c: RouteCoordinate) -> (Double, Double) {
            ((c.longitude - point.longitude) * metersPerDegreeLon, (c.latitude - point.latitude) * metersPerDegreeLat)
        }
        var best: Projection?
        for index in 0..<(path.count - 1) {
            let segmentStart = cumulative[index], segmentEnd = cumulative[index + 1]
            if let range = alongRange, segmentEnd < range.lowerBound || segmentStart > range.upperBound { continue }
            let (ax, ay) = xy(path[index]), (bx, by) = xy(path[index + 1])
            let dx = bx - ax, dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared > 0 ? min(1, max(0, -(ax * dx + ay * dy) / lengthSquared)) : 0
            let px = ax + t * dx, py = ay + t * dy
            let distance = (px * px + py * py).squareRoot()
            if best == nil || distance < best!.distanceFromRoute {
                best = Projection(distanceFromRoute: distance, alongMeters: segmentStart + t * (segmentEnd - segmentStart))
            }
        }
        return best
    }

    /// The point `meters` along the route (clamped to its ends).
    public static func point(along meters: Double, path: [RouteCoordinate], cumulative: [Double]) -> RouteCoordinate? {
        guard let first = path.first else { return nil }
        guard meters > 0 else { return first }
        guard let index = cumulative.firstIndex(where: { $0 >= meters }) else { return path.last }
        guard index > 0 else { return first }
        let a = path[index - 1], b = path[index]
        let span = cumulative[index] - cumulative[index - 1]
        let t = span > 0 ? (meters - cumulative[index - 1]) / span : 0
        return RouteCoordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Fewer points, keeping the shape to within `tolerance` metres (Douglas–Peucker).
    public static func simplify(_ path: [RouteCoordinate], tolerance: Double) -> [RouteCoordinate] {
        guard path.count > 2 else { return path }
        var keep = Array(repeating: false, count: path.count)
        keep[0] = true
        keep[path.count - 1] = true
        var stack = [(0, path.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var farthest = start, maxDistance = 0.0
            let segment = [path[start], path[end]]
            let cumulative = [0, path[start].distance(to: path[end])]
            for index in (start + 1)..<end {
                let distance = project(path[index], onto: segment, cumulative: cumulative)?.distanceFromRoute ?? 0
                if distance > maxDistance {
                    maxDistance = distance
                    farthest = index
                }
            }
            if maxDistance > tolerance {
                keep[farthest] = true
                stack.append((start, farthest))
                stack.append((farthest, end))
            }
        }
        return path.indices.filter { keep[$0] }.map { path[$0] }
    }

    /// Turn-by-turn directions worked out from the shape of the line (for straight-line and
    /// imported routes, which have no street directions).
    public static func turnInstructions(_ path: [RouteCoordinate]) -> [RouteInstruction] {
        let simple = simplify(path, tolerance: 8)
        guard simple.count > 2 else { return [] }
        let along = cumulative(simple)
        var result: [RouteInstruction] = []
        for index in 1..<(simple.count - 1) {
            // Ignore wiggles on very short legs.
            guard simple[index - 1].distance(to: simple[index]) >= 15, simple[index].distance(to: simple[index + 1]) >= 15 else { continue }
            let angle = turnAngle(from: bearing(simple[index - 1], simple[index]), to: bearing(simple[index], simple[index + 1]))
            let side = angle > 0 ? "right" : "left"
            let text: String
            switch abs(angle) {
            case ..<35: continue
            case ..<65: text = "Bear \(side)"
            case ..<150: text = "Turn \(side)"
            default: text = "Turn around"
            }
            // Two turns very close together read as one.
            if let last = result.last, along[index] - last.distanceMeters < 20 { continue }
            result.append(RouteInstruction(distanceMeters: along[index], text: text))
        }
        return result
    }
}

// MARK: - Loop generator

public enum LoopGenerator {
    /// Waypoints for a loop of roughly `targetMeters` that starts and ends at `start`, heading
    /// off on `bearingDegrees`. Points sit on a circle; `roadFactor` allows for roads being
    /// longer than straight lines (re-run with `adjustedRoadFactor` to home in on the distance).
    public static func waypoints(start: RouteCoordinate, targetMeters: Double, bearingDegrees: Double,
                                 roadFactor: Double = 1.25, points: Int = 3) -> [RouteCoordinate] {
        let radius = targetMeters / (2 * .pi * max(roadFactor, 0.5))
        let heading = bearingDegrees * .pi / 180
        let (centerLat, centerLon) = Geo.offset(latitude: start.latitude, longitude: start.longitude,
                                                northMeters: radius * cos(heading), eastMeters: radius * sin(heading))
        var result = [start]
        // The start is on the circle opposite the heading; walk round it clockwise.
        for k in 1...max(points, 2) {
            let angle = heading + .pi + Double(k) * 2 * .pi / Double(max(points, 2) + 1)
            let (lat, lon) = Geo.offset(latitude: centerLat, longitude: centerLon,
                                        northMeters: radius * cos(angle), eastMeters: radius * sin(angle))
            result.append(RouteCoordinate(latitude: lat, longitude: lon))
        }
        result.append(start)
        return result
    }

    /// The road factor to use next time, given how long the last attempt came out.
    public static func adjustedRoadFactor(_ factor: Double, achievedMeters: Double, targetMeters: Double) -> Double {
        guard targetMeters > 0, achievedMeters > 0 else { return factor }
        return min(max(factor * achievedMeters / targetMeters, 0.8), 3)
    }

    /// Within 10% of the target.
    public static func isCloseEnough(achievedMeters: Double, targetMeters: Double) -> Bool {
        abs(achievedMeters - targetMeters) <= targetMeters * 0.1
    }
}

// MARK: - Following a route

/// Tracks a runner along a planned route: progress, the next direction, and whether they've
/// gone off route. Feed it GPS fixes; it returns things to say.
public struct RouteGuide: Sendable {
    public struct Config: Equatable, Sendable {
        public var offRouteMeters: Double = 40
        public var backOnRouteMeters: Double = 25
        /// Fixes in a row beyond `offRouteMeters` before warning (ignores GPS jumps).
        public var offRouteConfirmFixes: Int = 4
        public var announceAheadMeters: Double = 120
        public var announceNowMeters: Double = 25
        public var finishMeters: Double = 30
        public var units: UnitSystem = .metric

        public init(units: UnitSystem = .metric) {
            self.units = units
        }
    }

    public enum Event: Equatable, Sendable {
        case upcoming(String, inMeters: Double)
        case now(String)
        case offRoute
        case backOnRoute
        case finished

        public func announcement(units: UnitSystem) -> String {
            switch self {
            case .upcoming(let text, let meters):
                return "In \(Self.spokenDistance(meters, units: units)), \(text.prefix(1).lowercased() + text.dropFirst())."
            case .now(let text): return text.hasSuffix(".") ? text : text + "."
            case .offRoute: return "You're off route. Head back to the line on the map."
            case .backOnRoute: return "Back on route."
            case .finished: return "You've reached the end of your route."
            }
        }

        static func spokenDistance(_ meters: Double, units: UnitSystem) -> String {
            switch units {
            case .metric: return "\(Int((meters / 10).rounded() * 10)) metres"
            case .imperial: return "\(Int((meters * 1.09361 / 10).rounded() * 10)) yards"
            }
        }
    }

    public let route: PlannedRoute
    public let config: Config
    private let cumulative: [Double]

    public private(set) var alongMeters: Double = 0
    public private(set) var distanceFromRoute: Double = 0
    public private(set) var isOffRoute = false
    public private(set) var isFinished = false
    private var nextIndex = 0
    private var announcedAhead = false
    private var offFixes = 0
    private var hasStarted = false

    public init(route: PlannedRoute, config: Config = Config()) {
        self.route = route
        self.config = config
        self.cumulative = RouteGeometry.cumulative(route.path)
    }

    public var totalMeters: Double { cumulative.last ?? 0 }
    public var remainingMeters: Double { max(0, totalMeters - alongMeters) }
    public var nextInstruction: RouteInstruction? { nextIndex < route.instructions.count ? route.instructions[nextIndex] : nil }
    public var distanceToNext: Double? { nextInstruction.map { max(0, $0.distanceMeters - alongMeters) } }

    public mutating func update(latitude: Double, longitude: Double) -> [Event] {
        guard route.path.count > 1, !isFinished else { return [] }
        let point = RouteCoordinate(latitude: latitude, longitude: longitude)
        // Look a little behind and ahead of where we were, so a route that crosses or doubles
        // back on itself doesn't jump to the wrong part.
        let window = (alongMeters - 100)...(alongMeters + (hasStarted ? 400 : 1000))
        var projection = RouteGeometry.project(point, onto: route.path, cumulative: cumulative, alongRange: window)
        if projection.map({ $0.distanceFromRoute > config.offRouteMeters }) ?? true {
            // Off the expected stretch: rejoining anywhere further on counts (a shortcut).
            if let ahead = RouteGeometry.project(point, onto: route.path, cumulative: cumulative,
                                                 alongRange: max(0, alongMeters - 100)...totalMeters),
               ahead.distanceFromRoute < (projection?.distanceFromRoute ?? .infinity) {
                projection = ahead
            }
        }
        guard let projection else { return [] }
        distanceFromRoute = projection.distanceFromRoute

        var events: [Event] = []
        if projection.distanceFromRoute > config.offRouteMeters {
            offFixes += 1
            if !isOffRoute && offFixes >= config.offRouteConfirmFixes {
                isOffRoute = true
                events.append(.offRoute)
            }
            return events
        }
        offFixes = 0
        hasStarted = true
        if isOffRoute && projection.distanceFromRoute <= config.backOnRouteMeters {
            isOffRoute = false
            events.append(.backOnRoute)
        }
        alongMeters = max(alongMeters, projection.alongMeters)
        guard !isOffRoute else { return events }

        // Skip directions already passed (e.g. after a shortcut).
        while let next = nextInstruction, next.distanceMeters < alongMeters - config.announceNowMeters {
            nextIndex += 1
            announcedAhead = false
        }
        if let next = nextInstruction, let toGo = distanceToNext {
            if toGo <= config.announceNowMeters {
                events.append(.now(next.text))
                nextIndex += 1
                announcedAhead = false
            } else if toGo <= config.announceAheadMeters && !announcedAhead {
                events.append(.upcoming(next.text, inMeters: toGo))
                announcedAhead = true
            }
        }
        if remainingMeters <= config.finishMeters && alongMeters > config.finishMeters {
            isFinished = true
            events.append(.finished)
        }
        return events
    }
}

// MARK: - GPX

public enum GPXRoute {
    /// Reads a GPX file: track points, else route points, else waypoints.
    public static func parse(_ text: String) -> (name: String?, points: [RouteCoordinate]) {
        let name = firstElement("name", in: text).map(unescape)
        for tag in ["trkpt", "rtept", "wpt"] {
            let points = coordinates(tag: tag, in: text)
            if points.count > 1 { return (name, points) }
        }
        return (name, [])
    }

    /// A GPX file of the route's line (no times), for other apps and devices.
    public static func gpx(name: String, path: [RouteCoordinate], creator: String = "Kinetix") -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="\#(GPXBuilder.escape(creator))" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <trk>",
            "    <name>\(GPXBuilder.escape(name))</name>",
            "    <type>running</type>",
            "    <trkseg>"
        ]
        for point in path {
            lines.append(#"      <trkpt lat="\#(format(point.latitude))" lon="\#(format(point.longitude))"/>"#)
        }
        lines += ["    </trkseg>", "  </trk>", "</gpx>"]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func coordinates(tag: String, in text: String) -> [RouteCoordinate] {
        var result: [RouteCoordinate] = []
        var searchRange = text.startIndex..<text.endIndex
        while let open = text.range(of: "<\(tag)", range: searchRange) {
            guard let close = text.range(of: ">", range: open.upperBound..<text.endIndex) else { break }
            // `<trkpt` but not `<trkpts…`.
            let next = text[open.upperBound]
            if next == " " || next == "\t" || next == "\n" || next == "\r" {
                let element = String(text[open.upperBound..<close.lowerBound])
                if let lat = attribute("lat", in: element).flatMap(Double.init),
                   let lon = attribute("lon", in: element).flatMap(Double.init),
                   (-90...90).contains(lat), (-180...180).contains(lon) {
                    result.append(RouteCoordinate(latitude: lat, longitude: lon))
                }
            }
            searchRange = close.upperBound..<text.endIndex
        }
        return result
    }

    private static func attribute(_ name: String, in element: String) -> String? {
        for quote in ["\"", "'"] {
            var searchRange = element.startIndex..<element.endIndex
            while let found = element.range(of: "\(name)=\(quote)", range: searchRange) {
                // Whole attribute name only (not e.g. "xlat").
                let isStart = found.lowerBound == element.startIndex
                    || element[element.index(before: found.lowerBound)].isWhitespace
                if isStart, let end = element.range(of: quote, range: found.upperBound..<element.endIndex) {
                    return String(element[found.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                searchRange = found.upperBound..<element.endIndex
            }
        }
        return nil
    }

    private static func firstElement(_ name: String, in text: String) -> String? {
        guard let open = text.range(of: "<\(name)>"),
              let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex) else { return nil }
        let value = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func format(_ value: Double) -> String {
        String(describing: (value * 10_000_000).rounded() / 10_000_000)
    }
}
