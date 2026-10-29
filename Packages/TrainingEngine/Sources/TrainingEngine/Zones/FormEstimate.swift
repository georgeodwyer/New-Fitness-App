import Foundation

/// Current fitness (a VDOT) from recent training, so race predictions follow progress:
/// best efforts over 1 km or more, and interval reps run against their targets.
public enum FormEstimate {
    /// What one run tells us.
    public struct Evidence: Equatable, Sendable {
        public var date: Date
        /// Fastest times this run covered each standard distance in.
        public var bestEfforts: [BestEffortDistance: Double]
        /// Average pace of each interval rep (VO2max reps), when the run had them.
        public var intervalRepPaces: [Pace]

        public init(date: Date, bestEfforts: [BestEffortDistance: Double], intervalRepPaces: [Pace] = []) {
            self.date = date
            self.bestEfforts = bestEfforts
            self.intervalRepPaces = intervalRepPaces
        }
    }

    public struct Result: Equatable, Sendable {
        public var vdot: Double
        /// How many runs backed it up.
        public var sessions: Int
    }

    /// VDOT the oxygen cost of a pace implies when run at `fractionOfMax` of VO2max.
    static func vdot(pace: Pace, fractionOfMax: Double) -> Double {
        let velocity = 60_000 / max(pace.secondsPerKm, 1) // metres per minute
        let vo2 = -4.60 + 0.182258 * velocity + 0.000104 * velocity * velocity
        return vo2 / fractionOfMax
    }

    /// The best signals from the last six weeks (up to three within 3% of the best, averaged), held within 5% of
    /// the current figure so one odd run can't swing it. nil with fewer than two signals.
    public static func estimate(_ runs: [Evidence], current: Double, now: Date) -> Result? {
        let from = now.addingTimeInterval(-42 * 86_400)
        var candidates: [Double] = []
        var sessions = 0
        for run in runs where run.date >= from && run.date <= now {
            var found = false
            // Training efforts aren't races: 5K and longer count as they are, shorter ones
            // (a fast km within a session) are discounted.
            for (distance, seconds) in run.bestEfforts where seconds > 0 {
                let raw = PaceZones.vdot(for: RaceResult(distanceMeters: distance.meters, timeSeconds: seconds))
                let value = distance.meters >= 5000 ? raw : raw * 0.95
                if value > 20 && value < 90 { candidates.append(value); found = true }
            }
            // Interval reps sit at about 98% of VO2max.
            if run.intervalRepPaces.count >= 3 {
                let sorted = run.intervalRepPaces.map(\.secondsPerKm).sorted()
                let median = sorted[sorted.count / 2]
                let value = vdot(pace: Pace(secondsPerKm: median), fractionOfMax: 0.98)
                if value > 20 && value < 90 { candidates.append(value); found = true }
            }
            if found { sessions += 1 }
        }
        guard candidates.count >= 2, sessions >= 1 else { return nil }
        // Most runs aren't flat out, so only efforts close to the best one count.
        let best = candidates.max() ?? 0
        let top = candidates.filter { $0 >= best * 0.97 }.sorted(by: >).prefix(3)
        let average = top.reduce(0, +) / Double(top.count)
        let held = min(max(average, current * 0.95), current * 1.05)
        return Result(vdot: held, sessions: sessions)
    }
}
