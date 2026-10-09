import Foundation

/// A GPS fix as delivered by CoreLocation (or a simulator).
public struct LocationSample: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var latitude: Double
    public var longitude: Double
    /// Metres; larger is worse. Negative means invalid.
    public var horizontalAccuracy: Double
    /// Metres per second from the GPS chip (Doppler); negative when unavailable.
    public var speed: Double

    public init(timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double = 5, speed: Double = -1) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
    }
}

/// A stored route point (compact; used for maps and summaries).
public struct RoutePoint: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Seconds of active (unpaused) running when this point was recorded.
    public var elapsed: Double

    public init(latitude: Double, longitude: Double, elapsed: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.elapsed = elapsed
    }
}

public enum Geo {
    static let earthRadius = 6_371_000.0

    /// Great-circle distance in metres.
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthRadius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// The point `meters` away from a coordinate along a bearing (radians, 0 = north).
    public static func offset(latitude: Double, longitude: Double, northMeters: Double, eastMeters: Double) -> (Double, Double) {
        let dLat = northMeters / earthRadius * 180 / .pi
        let dLon = eastMeters / (earthRadius * cos(latitude * .pi / 180)) * 180 / .pi
        return (latitude + dLat, longitude + dLon)
    }
}
