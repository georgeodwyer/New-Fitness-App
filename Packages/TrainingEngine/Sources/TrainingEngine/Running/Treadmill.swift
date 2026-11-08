import Foundation

// Treadmill runs: no GPS, so distance comes from the phone's step counter, the watch or the
// speed set on the treadmill. At the end the runner can type in what the treadmill showed and
// the whole run is scaled to match.

extension RunSummary {
    /// The run with its distance corrected to `meters` (what the treadmill said). Splits are
    /// worked out again along the same timeline; steps and laps are scaled.
    public func correctedDistance(to meters: Double, units: UnitSystem) -> RunSummary {
        guard meters > 0, distanceMeters > 0, abs(meters - distanceMeters) > 1 else { return self }
        let factor = meters / distanceMeters
        let unit = units == .metric ? 1000.0 : Units.metersPerMile

        // The timeline (time, distance) at each old split, scaled.
        var points: [(time: Double, distance: Double)] = [(0, 0)]
        var time = 0.0
        for (index, split) in splits.enumerated() {
            time += split.durationSeconds
            points.append((time, Double(index + 1) * unit * factor))
        }
        points.append((durationSeconds, meters))
        func timeAt(_ distance: Double) -> Double? {
            for (a, b) in zip(points, points.dropFirst()) where distance <= b.distance && b.distance > a.distance {
                return a.time + (distance - a.distance) / (b.distance - a.distance) * (b.time - a.time)
            }
            return nil
        }
        var newSplits: [Split] = []
        var previous = 0.0
        var k = 1
        while Double(k) * unit <= meters, let at = timeAt(Double(k) * unit) {
            let duration = at - previous
            let old = splits.isEmpty ? nil : splits[min(k - 1, splits.count - 1)]
            newSplits.append(Split(index: k, durationSeconds: duration, pace: Pace(secondsPerKm: duration / unit * 1000),
                                   averagePace: Pace(secondsPerKm: at / (Double(k) * unit) * 1000), averageHeartRate: old?.averageHeartRate))
            previous = at
            k += 1
        }

        var copy = self
        copy.distanceMeters = meters
        copy.averagePace = durationSeconds > 0 ? Pace(secondsPerKm: durationSeconds / meters * 1000) : nil
        copy.splits = newSplits
        copy.segments = segments.map { result in
            var result = result
            result.distanceMeters *= factor
            result.averagePace = result.distanceMeters > 0 ? Pace(secondsPerKm: result.durationSeconds / result.distanceMeters * 1000) : nil
            return result
        }
        copy.laps = laps?.map { lap in
            var lap = lap
            lap.distanceMeters *= factor
            return lap
        }
        return copy
    }
}

extension PaceRange {
    /// The treadmill speed for this pace range (its middle), km/h.
    public var treadmillKilometresPerHour: Double {
        Pace(secondsPerKm: (fastest.secondsPerKm + slowest.secondsPerKm) / 2).kilometresPerHour
    }
}

public enum TreadmillSpeed {
    /// "15.0 km/h" or "9.3 mph".
    public static func text(kilometresPerHour: Double, units: UnitSystem) -> String {
        units == .imperial ? String(format: "%.1f mph", kilometresPerHour / 1.609344) : String(format: "%.1f km/h", kilometresPerHour)
    }

    /// Spoken: "15 kilometres an hour", "9.5 miles an hour".
    public static func spoken(kilometresPerHour: Double, units: UnitSystem) -> String {
        let value = units == .imperial ? kilometresPerHour / 1.609344 : kilometresPerHour
        let rounded = (value * 10).rounded() / 10
        let number = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return "\(number) \(units == .imperial ? "miles" : "kilometres") an hour"
    }
}
