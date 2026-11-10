import Foundation

/// Current fitness (a VDOT) from recent training, so race predictions follow progress:
/// best efforts over 1 km or more, and interval reps run against their targets.
public enum FormEstimate {
    /// One rep of a session: the pace run and the pace it was set at.
    public struct Rep: Equatable, Sendable {
        public var pace: Pace
        /// The middle of the rep's target range.
        public var target: Pace

        public init(pace: Pace, target: Pace) {
            self.pace = pace
            self.target = target
        }
    }

    /// What one run tells us.
    public struct Evidence: Equatable, Sendable {
        public var date: Date
        /// Fastest times this run covered each standard distance in.
        public var bestEfforts: [BestEffortDistance: Double]
        /// Average pace of each interval rep (VO2max reps), when the run had them and no targets are known.
        public var intervalRepPaces: [Pace]
        /// Reps run against a target pace (10K pace, 5K pace, intervals…).
        public var reps: [Rep]

        public init(date: Date, bestEfforts: [BestEffortDistance: Double], intervalRepPaces: [Pace] = [], reps: [Rep] = []) {
            self.date = date
            self.bestEfforts = bestEfforts
            self.intervalRepPaces = intervalRepPaces
            self.reps = reps
        }
    }

    public struct Result: Equatable, Sendable {
        public var vdot: Double
        /// How many runs backed it up.
        public var sessions: Int
    }

    /// Oxygen cost of running at a pace (ml/kg/min).
    static func oxygenCost(_ pace: Pace) -> Double {
        let velocity = 60_000 / max(pace.secondsPerKm, 1) // metres per minute
        return -4.60 + 0.182258 * velocity + 0.000104 * velocity * velocity
    }

    /// VDOT the oxygen cost of a pace implies when run at `fractionOfMax` of VO2max.
    static func vdot(pace: Pace, fractionOfMax: Double) -> Double {
        oxygenCost(pace) / fractionOfMax
    }

    /// Fitness that reps run against their targets imply: targets come from the current fitness,
    /// so reps run 3% quicker than set (in oxygen cost) mean fitness about 3% higher, whatever the
    /// zone (10K pace, 5K pace or VO2max). The middle rep counts, so one fast or slow rep can't swing it.
    static func vdot(reps: [Rep], current: Double) -> Double? {
        let ratios = reps.compactMap { rep -> Double? in
            let target = oxygenCost(rep.target)
            return target > 0 ? oxygenCost(rep.pace) / target : nil
        }.sorted()
        guard ratios.count >= 3 else { return nil }
        return current * ratios[ratios.count / 2]
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
            // Reps against their targets.
            if let value = vdot(reps: run.reps, current: current), value > 20 && value < 90 {
                candidates.append(value); found = true
            } else if run.intervalRepPaces.count >= 3 {
                // No targets known: interval reps sit at about 98% of VO2max.
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
