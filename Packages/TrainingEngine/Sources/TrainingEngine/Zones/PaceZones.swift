import Foundation

/// Training intensities, from Jack Daniels' VDOT system.
public enum PaceZone: String, Codable, CaseIterable, Sendable {
    /// Easy and long runs, warm-ups and recoveries.
    case easy
    /// Marathon race pace.
    case marathon
    /// "Comfortably hard" tempo / lactate threshold.
    case threshold
    /// VO2max intervals (roughly 3k-5k race pace).
    case interval
    /// Short fast repetitions (roughly mile pace).
    case repetition
}

/// A runner's pace zones derived from a race result (or a default by experience).
public struct PaceZones: Codable, Equatable, Sendable {
    public let vdot: Double
    public let ranges: [PaceZone: PaceRange]

    /// Fraction-of-VDOT bands for each zone (slow end, fast end).
    static let intensityBands: [PaceZone: (slow: Double, fast: Double)] = [
        .easy: (0.62, 0.74),
        .marathon: (0.80, 0.84),
        .threshold: (0.86, 0.89),
        .interval: (0.96, 1.00),
        .repetition: (1.04, 1.08)
    ]

    /// Typical comfortable 5k times used when the user gives no race time.
    static let default5kSeconds: [ExperienceLevel: Double] = [
        .beginner: 33 * 60,
        .intermediate: 26 * 60,
        .advanced: 21 * 60
    ]

    public init(vdot: Double) {
        self.vdot = vdot
        var ranges: [PaceZone: PaceRange] = [:]
        for (zone, band) in Self.intensityBands {
            let slow = Self.pace(forVO2: band.slow * vdot)
            let fast = Self.pace(forVO2: band.fast * vdot)
            ranges[zone] = PaceRange(fastest: fast, slowest: slow)
        }
        self.ranges = ranges
    }

    public init(race: RaceResult) {
        self.init(vdot: Self.vdot(for: race))
    }

    /// Zones from the profile's race time, or a sensible default for the experience level.
    public init(profile: AthleteProfile) {
        if let race = profile.recentRace, race.distanceMeters > 0, race.timeSeconds > 0 {
            self.init(race: race)
        } else {
            let seconds = Self.default5kSeconds[profile.runningExperience] ?? 30 * 60
            self.init(race: RaceResult(distanceMeters: 5000, timeSeconds: seconds))
        }
    }

    public func range(for zone: PaceZone) -> PaceRange {
        // Every zone is populated in init.
        ranges[zone] ?? PaceRange(fastest: Pace(secondsPerKm: 360), slowest: Pace(secondsPerKm: 420))
    }

    /// Middle of a zone, used to estimate durations.
    public func typicalPace(for zone: PaceZone) -> Pace {
        let range = range(for: zone)
        return Pace(secondsPerKm: (range.fastest.secondsPerKm + range.slowest.secondsPerKm) / 2)
    }

    /// Daniels & Gilbert VDOT from a race performance.
    public static func vdot(for race: RaceResult) -> Double {
        let minutes = race.timeSeconds / 60
        let velocity = race.distanceMeters / minutes // metres per minute
        let vo2 = -4.60 + 0.182258 * velocity + 0.000104 * velocity * velocity
        let fraction = 0.8 + 0.1894393 * exp(-0.012778 * minutes) + 0.2989558 * exp(-0.1932605 * minutes)
        return vo2 / fraction
    }

    /// Inverse of the oxygen-cost equation: the pace that costs `vo2` ml/kg/min.
    static func pace(forVO2 vo2: Double) -> Pace {
        let a = 0.000104, b = 0.182258, c = -(4.60 + vo2)
        let velocity = (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a) // metres per minute
        return Pace(secondsPerKm: 60_000 / velocity)
    }

    /// Predicted race time for a distance at this VDOT (solves the VDOT equation for time).
    public func predictedTime(distanceMeters: Double) -> Double {
        // Bisection between generous bounds; VDOT(time) decreases as time increases.
        var low = distanceMeters / 1000 * 120.0   // 2:00/km
        var high = distanceMeters / 1000 * 900.0  // 15:00/km
        for _ in 0..<60 {
            let mid = (low + high) / 2
            let v = Self.vdot(for: RaceResult(distanceMeters: distanceMeters, timeSeconds: mid))
            if v > vdot { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
}
