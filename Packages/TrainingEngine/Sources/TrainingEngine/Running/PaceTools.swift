import Foundation

/// The runner's calculators: pace, time and distance, and splits for a goal time.
public enum PaceTools {
    /// Seconds to cover a distance at a pace.
    public static func time(distanceMeters: Double, pace: Pace) -> Double {
        distanceMeters / 1000 * pace.secondsPerKm
    }

    /// The pace that covers a distance in a time (nil for nonsense input).
    public static func pace(distanceMeters: Double, seconds: Double) -> Pace? {
        guard distanceMeters > 0, seconds > 0 else { return nil }
        return Pace(secondsPerKm: seconds / (distanceMeters / 1000))
    }

    /// The distance covered in a time at a pace.
    public static func distance(seconds: Double, pace: Pace) -> Double? {
        guard seconds > 0, pace.secondsPerKm > 0 else { return nil }
        return seconds / pace.secondsPerKm * 1000
    }

    public struct PlannedSplit: Equatable, Sendable, Identifiable {
        public var index: Int
        /// This split's length (the last one can be shorter, e.g. the 0.1 of a half).
        public var meters: Double
        public var seconds: Double
        /// Time at the end of this split.
        public var cumulativeSeconds: Double
        public var pace: Pace
        public var id: Int { index }
    }

    /// Splits for a goal time over a distance, per `splitMeters` (1 km or a mile).
    /// - Parameter negativeSplit: how much faster the second half is than the first, as a
    ///   fraction of the average pace (0 = even, 0.02 = second half about 2% faster). The pace
    ///   changes steadily through the race and the total always comes to the goal time.
    public static func splits(distanceMeters: Double, goalSeconds: Double, splitMeters: Double,
                              negativeSplit: Double = 0) -> [PlannedSplit] {
        guard distanceMeters > 0, goalSeconds > 0, splitMeters > 0 else { return [] }
        var lengths: [Double] = []
        var covered = 0.0
        while covered < distanceMeters - 0.5 {
            let length = min(splitMeters, distanceMeters - covered)
            lengths.append(length)
            covered += length
        }
        // Pace multiplier at each split's middle: slower at the start, faster at the end. A
        // straight line from +s to -s across the race makes the halves differ by about s.
        let s = max(0, negativeSplit)
        var start = 0.0
        let weights = lengths.map { length -> Double in
            let middle = (start + length / 2) / distanceMeters
            start += length
            return 1 + s * (1 - 2 * middle)
        }
        let average = goalSeconds / distanceMeters // seconds per metre
        let scale = goalSeconds / zip(lengths, weights).reduce(0) { $0 + $1.0 * $1.1 * average }
        var total = 0.0
        return lengths.enumerated().map { index, length in
            let secondsPerMeter = average * weights[index] * scale
            let seconds = secondsPerMeter * length
            total += seconds
            return PlannedSplit(index: index + 1, meters: length, seconds: seconds, cumulativeSeconds: total,
                                pace: Pace(secondsPerKm: secondsPerMeter * 1000))
        }
    }
}
