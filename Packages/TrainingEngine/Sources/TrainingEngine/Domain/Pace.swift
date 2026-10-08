import Foundation

/// Running pace, stored as seconds per kilometre (lower is faster).
public struct Pace: Codable, Equatable, Comparable, Hashable, Sendable {
    public var secondsPerKm: Double

    public init(secondsPerKm: Double) {
        self.secondsPerKm = secondsPerKm
    }

    /// Pace from a speed in metres per second. Returns nil for a standstill.
    public init?(metersPerSecond: Double) {
        guard metersPerSecond > 0.1 else { return nil }
        self.secondsPerKm = 1000 / metersPerSecond
    }

    public var secondsPerMile: Double { secondsPerKm * Units.metersPerMile / 1000 }

    public func seconds(per units: UnitSystem) -> Double {
        units == .metric ? secondsPerKm : secondsPerMile
    }

    public static func < (lhs: Pace, rhs: Pace) -> Bool {
        lhs.secondsPerKm < rhs.secondsPerKm
    }
}

/// A target pace window. `fastest` has the lower seconds-per-km value.
public struct PaceRange: Codable, Equatable, Hashable, Sendable {
    public var fastest: Pace
    public var slowest: Pace

    public init(fastest: Pace, slowest: Pace) {
        self.fastest = min(fastest, slowest)
        self.slowest = max(fastest, slowest)
    }

    public enum Position: Equatable, Sendable {
        case tooFast, onTarget, tooSlow
    }

    /// Where `pace` sits relative to this range, allowing `toleranceSecondsPerKm` either side.
    public func position(of pace: Pace, toleranceSecondsPerKm: Double = 0) -> Position {
        if pace.secondsPerKm < fastest.secondsPerKm - toleranceSecondsPerKm { return .tooFast }
        if pace.secondsPerKm > slowest.secondsPerKm + toleranceSecondsPerKm { return .tooSlow }
        return .onTarget
    }
}
