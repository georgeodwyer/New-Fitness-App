import Foundation

/// The runner's recent running, worked out from the runs the app knows about (recorded in
/// Kinetix, imported from Strava, and other apps' runs in Apple Health), used to pre-fill
/// "How far do you run in a typical week?" and to restart a programme.
public enum RecentRunning {
    public struct Run: Equatable, Sendable {
        public var start: Date
        public var meters: Double

        public init(start: Date, meters: Double) {
            self.start = start
            self.meters = meters
        }
    }

    public struct Summary: Equatable, Sendable {
        /// Average a week over the period.
        public var weeklyMeters: Double
        public var longestMeters: Double
        public var runCount: Int
    }

    /// `primary` plus the runs in `other` that aren't the same run (one starting within
    /// 15 minutes of a primary run is taken to be a copy, e.g. a Strava run also in Health).
    public static func merge(primary: [Run], other: [Run]) -> [Run] {
        primary + other.filter { run in !primary.contains { abs($0.start.timeIntervalSince(run.start)) < 15 * 60 } }
    }

    /// Weekly average and longest run over the last `days` (nil if there were no runs).
    public static func summary(_ runs: [Run], now: Date, days: Int = 28) -> Summary? {
        let from = now.addingTimeInterval(-Double(days) * 86_400)
        let recent = runs.filter { $0.start >= from && $0.start <= now && $0.meters > 0 }
        guard !recent.isEmpty else { return nil }
        let total = recent.reduce(0) { $0 + $1.meters }
        return Summary(weeklyMeters: total / (Double(days) / 7), longestMeters: recent.map(\.meters).max() ?? 0, runCount: recent.count)
    }
}
