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
    /// Relaxed but purposeful: marathon pace plus 10–20 s/km.
    case steady
    /// Predicted half-marathon race pace.
    case halfMarathon
    /// Predicted 10K race pace.
    case tenK
    /// Predicted 5K race pace.
    case fiveK

    /// Race-pace zones, worked out from the predicted time for the distance.
    var raceDistanceMeters: Double? {
        switch self {
        case .halfMarathon: return 21_097.5
        case .tenK: return 10_000
        case .fiveK: return 5_000
        default: return nil
        }
    }
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
        for zone in PaceZone.allCases {
            ranges[zone] = Self.computeRange(zone, vdot: vdot)
        }
        self.ranges = ranges
    }

    /// A zone's range at a VDOT.
    static func computeRange(_ zone: PaceZone, vdot: Double) -> PaceRange {
        if let band = intensityBands[zone] {
            return PaceRange(fastest: pace(forVO2: band.fast * vdot), slowest: pace(forVO2: band.slow * vdot))
        }
        if let distance = zone.raceDistanceMeters {
            // Race pace, give or take 3 s/km.
            let zones = PaceZones(vdotOnly: vdot)
            let perKm = zones.predictedTime(distanceMeters: distance) / (distance / 1000)
            return PaceRange(fastest: Pace(secondsPerKm: perKm - 3), slowest: Pace(secondsPerKm: perKm + 3))
        }
        // Steady: marathon pace plus 10–20 s/km.
        let marathon = computeRange(.marathon, vdot: vdot)
        let middle = (marathon.fastest.secondsPerKm + marathon.slowest.secondsPerKm) / 2
        return PaceRange(fastest: Pace(secondsPerKm: middle + 10), slowest: Pace(secondsPerKm: middle + 20))
    }

    /// Just the VDOT (for race predictions while the ranges are being worked out).
    private init(vdotOnly: Double) {
        self.vdot = vdotOnly
        self.ranges = [:]
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
        // Zones saved before a zone was added are worked out from the VDOT.
        ranges[zone] ?? Self.computeRange(zone, vdot: vdot)
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
