import Foundation

// MARK: - Track geometry

/// A standard 400 m running track: two 84.39 m straights joined by two bends, run anticlockwise.
/// Lane 1 is measured 0.3 m from the kerb (36.5 m radius); other lanes 0.2 m from their inside
/// line, each lane 1.22 m wide. Lane 1 is 400 m, each lane out about 7 m more.
public enum TrackGeometry {
    public static let straight = 84.39
    public static let kerbRadius = 36.5
    public static let laneWidth = 1.22
    public static let lanes = 1...8

    /// Radius of the running line in a lane.
    public static func radius(lane: Int) -> Double {
        let lane = min(max(lane, 1), 8)
        return lane == 1 ? kerbRadius + 0.3 : kerbRadius + laneWidth * Double(lane - 1) + 0.2
    }

    /// One lap in a lane, in metres (lane 1 = 400 m).
    public static func lapLength(lane: Int) -> Double {
        2 * straight + 2 * Double.pi * radius(lane: lane)
    }
}

/// Where a track is: its centre, which way its straights run, and the radius that fits the GPS.
public struct TrackFit: Codable, Equatable, Sendable {
    /// Centre of the track.
    public var latitude: Double
    public var longitude: Double
    /// Direction of the straights, radians from east (anticlockwise).
    public var angle: Double
    /// Radius that best fitted the GPS (a guide to the lane, not exact).
    public var fittedRadius: Double
    /// Root-mean-square distance of the GPS points from the fitted shape, metres.
    public var residual: Double

    public init(latitude: Double, longitude: Double, angle: Double, fittedRadius: Double, residual: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.angle = angle
        self.fittedRadius = fittedRadius
        self.residual = residual
    }

    // Local flat coordinates around the centre (metres east and north).
    private static let metresPerDegreeLatitude = 110_540.0
    private var metresPerDegreeLongitude: Double { 111_320 * cos(latitude * .pi / 180) }

    /// A GPS position in the track's own frame: `u` along the straights, `v` across.
    func local(_ lat: Double, _ lon: Double) -> (u: Double, v: Double) {
        let x = (lon - longitude) * metresPerDegreeLongitude
        let y = (lat - latitude) * Self.metresPerDegreeLatitude
        let c = cos(angle), s = sin(angle)
        return (x * c + y * s, -x * s + y * c)
    }

    func coordinate(u: Double, v: Double) -> (latitude: Double, longitude: Double) {
        let c = cos(angle), s = sin(angle)
        let x = u * c - v * s
        let y = u * s + v * c
        return (latitude + y / Self.metresPerDegreeLatitude, longitude + x / metresPerDegreeLongitude)
    }

    /// Where a GPS position is along a lane (metres from the start of the bottom straight,
    /// anticlockwise), how far it is from that lane's line, and the point on the line.
    public func project(latitude lat: Double, longitude lon: Double, lane: Int) -> (position: Double, offset: Double,
                                                                                      latitude: Double, longitude: Double) {
        let p = local(lat, lon)
        let r = TrackGeometry.radius(lane: lane)
        let result = Self.project(u: p.u, v: p.v, radius: r)
        let point = coordinate(u: result.u, v: result.v)
        // The start line is 0 (not a full lap round).
        let length = TrackGeometry.lapLength(lane: lane)
        var position = result.position.truncatingRemainder(dividingBy: length)
        if position < 0 { position += length }
        if length - position < 1e-6 { position = 0 }
        return (position, result.offset, point.latitude, point.longitude)
    }

    /// The point `position` metres round a lane (from the start of the bottom straight, anticlockwise).
    public func coordinate(atPosition position: Double, lane: Int) -> (latitude: Double, longitude: Double) {
        let r = TrackGeometry.radius(lane: lane)
        let straight = TrackGeometry.straight, half = straight / 2, bend = Double.pi * r
        let length = 2 * straight + 2 * bend
        var s = position.truncatingRemainder(dividingBy: length)
        if s < 0 { s += length }
        let u: Double, v: Double
        if s < straight {
            u = -half + s; v = -r
        } else if s < straight + bend {
            let theta = -Double.pi / 2 + (s - straight) / r
            u = half + r * cos(theta); v = r * sin(theta)
        } else if s < 2 * straight + bend {
            u = half - (s - straight - bend); v = r
        } else {
            let theta = Double.pi / 2 + (s - 2 * straight - bend) / r
            u = -half + r * cos(theta); v = r * sin(theta)
        }
        return coordinate(u: u, v: v)
    }

    /// Nearest point on a stadium of radius `r` to (u, v), with its arc position and distance.
    static func project(u: Double, v: Double, radius r: Double) -> (position: Double, offset: Double, u: Double, v: Double) {
        let half = TrackGeometry.straight / 2
        let straight = TrackGeometry.straight
        let bend = Double.pi * r
        if abs(u) <= half {
            if v < 0 {
                // Bottom straight, running towards +u.
                return (u + half, abs(v + r), u, -r)
            } else {
                // Top straight, running towards -u.
                return (straight + bend + (half - u), abs(v - r), u, r)
            }
        }
        let centreU = u > 0 ? half : -half
        let du = u - centreU
        let distanceFromCentre = max((du * du + v * v).squareRoot(), 0.001)
        let offset = abs(distanceFromCentre - r)
        let nu = centreU + du / distanceFromCentre * r
        let nv = v / distanceFromCentre * r
        var theta = atan2(v, du) // -π...π
        if u > 0 {
            // Right bend: -90° (bottom) to +90° (top).
            theta = min(max(theta, -Double.pi / 2), Double.pi / 2)
            return (straight + (theta + Double.pi / 2) * r, offset, nu, nv)
        } else {
            // Left bend: +90° (top) round to 270° (bottom).
            if theta < 0 { theta += 2 * Double.pi }
            theta = min(max(theta, Double.pi / 2), 3 * Double.pi / 2)
            return (2 * straight + bend + (theta - Double.pi / 2) * r, offset, nu, nv)
        }
    }
}

// MARK: - Finding a track in GPS

public enum TrackDetector {
    /// Fits the 400 m track shape to GPS points covering about a lap. Returns nil if they don't
    /// look like a track (too far off the shape, or not most of the way round).
    public static func fit(_ points: [(latitude: Double, longitude: Double)], maxResidual: Double = 7,
                           minCoverage: Double = 0.75) -> TrackFit? {
        guard points.count >= 20 else { return nil }
        let lat0 = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let lon0 = points.map(\.longitude).reduce(0, +) / Double(points.count)
        let mLon = 111_320 * cos(lat0 * .pi / 180), mLat = 110_540.0
        let xy = points.map { (x: ($0.longitude - lon0) * mLon, y: ($0.latitude - lat0) * mLat) }
        // A track is about 160 × 75 m: anything far off that isn't one.
        let n = Double(xy.count)
        let mx = xy.map(\.x).reduce(0, +) / n, my = xy.map(\.y).reduce(0, +) / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in xy { sxx += (p.x - mx) * (p.x - mx); syy += (p.y - my) * (p.y - my); sxy += (p.x - mx) * (p.y - my) }
        let angle0 = 0.5 * atan2(2 * sxy, sxx - syy)

        func cost(cx: Double, cy: Double, angle: Double, radius: Double) -> Double {
            let c = cos(angle), s = sin(angle)
            var total = 0.0
            for p in xy {
                let x = p.x - cx, y = p.y - cy
                let offset = TrackFit.project(u: x * c + y * s, v: -x * s + y * c, radius: radius).offset
                total += offset * offset
            }
            return total / n
        }

        var best = (cx: mx, cy: my, angle: angle0, radius: 38.0, cost: Double.infinity)
        // Coarse, then fine: centre ±10 m, angle ±10°, radius across the lanes.
        for radius in stride(from: 36.8, through: 46.0, by: 1.5) {
            for da in stride(from: -10.0, through: 10.0, by: 2.5) {
                for dx in stride(from: -10.0, through: 10.0, by: 2.5) {
                    for dy in stride(from: -10.0, through: 10.0, by: 2.5) {
                        let candidate = cost(cx: mx + dx, cy: my + dy, angle: angle0 + da * .pi / 180, radius: radius)
                        if candidate < best.cost { best = (mx + dx, my + dy, angle0 + da * .pi / 180, radius, candidate) }
                    }
                }
            }
        }
        let coarse = best
        for dr in stride(from: -0.75, through: 0.75, by: 0.75) {
            for da in stride(from: -1.5, through: 1.5, by: 0.5) {
                for dx in stride(from: -1.5, through: 1.5, by: 0.5) {
                    for dy in stride(from: -1.5, through: 1.5, by: 0.5) {
                        let radius = coarse.radius + dr, angle = coarse.angle + da * .pi / 180
                        let candidate = cost(cx: coarse.cx + dx, cy: coarse.cy + dy, angle: angle, radius: radius)
                        if candidate < best.cost { best = (coarse.cx + dx, coarse.cy + dy, angle, radius, candidate) }
                    }
                }
            }
        }
        let residual = best.cost.squareRoot()
        guard residual <= maxResidual else { return nil }
        let fit = TrackFit(latitude: lat0 + best.cy / mLat, longitude: lon0 + best.cx / mLon, angle: best.angle,
                           fittedRadius: best.radius, residual: residual)
        // Most of the way round: points in at least `minCoverage` of 16 equal parts of the lap.
        let length = TrackGeometry.lapLength(lane: 1)
        var bins = Set<Int>()
        for p in points {
            let position = fit.project(latitude: p.latitude, longitude: p.longitude, lane: 1).position
            bins.insert(min(15, Int(position / length * 16)))
        }
        guard Double(bins.count) / 16 >= minCoverage else { return nil }
        return fit
    }

    /// The last `meters` of a route (by distance between points), for fitting.
    public static func recent(_ route: [RoutePoint], meters: Double = 500) -> [(latitude: Double, longitude: Double)] {
        guard route.count >= 2 else { return [] }
        var result: [(latitude: Double, longitude: Double)] = [(route[route.count - 1].latitude, route[route.count - 1].longitude)]
        var covered = 0.0
        var index = route.count - 1
        while index > 0, covered < meters {
            let a = route[index], b = route[index - 1]
            covered += Geo.distance(a.latitude, a.longitude, b.latitude, b.longitude)
            result.append((b.latitude, b.longitude))
            index -= 1
        }
        return covered >= meters * 0.85 ? result.reversed() : []
    }
}

/// Track mode in use: the fitted track, the lane, and which way round they're running.
public struct TrackLock: Codable, Equatable, Sendable {
    public var fit: TrackFit
    public var lane: Int
    /// +1 anticlockwise (the usual way), -1 clockwise.
    public var direction: Double
    public var lapLength: Double { TrackGeometry.lapLength(lane: lane) }

    public init(fit: TrackFit, lane: Int, direction: Double = 1) {
        self.fit = fit
        self.lane = min(max(lane, 1), 8)
        self.direction = direction
    }

    /// Which way the points go round (by the sum of their steps along the lane).
    static func direction(of points: [(latitude: Double, longitude: Double)], fit: TrackFit, lane: Int) -> Double {
        let length = TrackGeometry.lapLength(lane: lane)
        var total = 0.0
        var last: Double?
        for p in points {
            let position = fit.project(latitude: p.latitude, longitude: p.longitude, lane: lane).position
            if let last { total += wrapped(position - last, length: length) }
            last = position
        }
        return total < 0 ? -1 : 1
    }

    /// A change in position, the short way round.
    static func wrapped(_ delta: Double, length: Double) -> Double {
        var d = delta.truncatingRemainder(dividingBy: length)
        if d > length / 2 { d -= length }
        if d < -length / 2 { d += length }
        return d
    }
}
