import Foundation

/// Standard race distances for best efforts.
public enum BestEffortDistance: Double, CaseIterable, Codable, Sendable, Identifiable {
    case oneKilometre = 1000
    case oneMile = 1609.344
    case fiveK = 5000
    case tenK = 10000
    case half = 21097.5
    case marathon = 42195

    public var id: Double { rawValue }
    public var meters: Double { rawValue }

    public var displayName: String {
        switch self {
        case .oneKilometre: return "1 km"
        case .oneMile: return "1 mile"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .half: return "Half marathon"
        case .marathon: return "Marathon"
        }
    }
}

/// One point of a chart over the course of a run.
public struct RunChartPoint: Equatable, Sendable, Identifiable {
    /// Seconds of active running.
    public var elapsed: Double
    public var value: Double
    public var id: Double { elapsed }

    public init(elapsed: Double, value: Double) {
        self.elapsed = elapsed
        self.value = value
    }
}

public enum RunAnalysis {
    /// Cumulative distance (m) at each route point.
    public static func cumulativeDistances(_ route: [RoutePoint]) -> [Double] {
        guard !route.isEmpty else { return [] }
        var result = [0.0]
        result.reserveCapacity(route.count)
        for index in 1..<route.count {
            let a = route[index - 1], b = route[index]
            result.append(result[index - 1] + Geo.distance(a.latitude, a.longitude, b.latitude, b.longitude))
        }
        return result
    }

    /// Fastest time (seconds) to cover `distance` anywhere within the run, interpolating
    /// between GPS points. nil if the run was shorter than the distance.
    public static func bestTime(over distance: Double, route: [RoutePoint]) -> Double? {
        let cumulative = cumulativeDistances(route)
        guard let total = cumulative.last, total >= distance, route.count >= 2 else { return nil }
        var best = Double.infinity
        var end = 0
        for start in 0..<route.count {
            let target = cumulative[start] + distance
            if target > total { break }
            if end < start { end = start }
            while end < route.count - 1 && cumulative[end] < target { end += 1 }
            // Interpolate the time at which `target` metres was reached, within (end-1, end].
            let segmentStart = max(start, end - 1)
            let d0 = cumulative[segmentStart], d1 = cumulative[end]
            let t0 = route[segmentStart].elapsed, t1 = route[end].elapsed
            let fraction = d1 > d0 ? (target - d0) / (d1 - d0) : 1
            let timeAtTarget = t0 + (t1 - t0) * min(max(fraction, 0), 1)
            let duration = timeAtTarget - route[start].elapsed
            if duration > 0 { best = min(best, duration) }
        }
        return best.isFinite ? best : nil
    }

    /// The route without its first and last `meters`, so a shared map doesn't show where
    /// you live. Short runs keep at least their middle third.
    public static func privacyTrimmed(_ route: [RoutePoint], meters: Double = 200) -> [RoutePoint] {
        let cumulative = cumulativeDistances(route)
        guard let total = cumulative.last, route.count > 2 else { return route }
        let trim = min(meters, total / 3)
        let kept = zip(route, cumulative).filter { $0.1 >= trim && $0.1 <= total - trim }.map(\.0)
        return kept.count >= 2 ? kept : route
    }

    /// Best times for every standard distance the run covered.
    public static func bestEfforts(route: [RoutePoint]) -> [BestEffortDistance: Double] {
        var result: [BestEffortDistance: Double] = [:]
        for distance in BestEffortDistance.allCases {
            if let time = bestTime(over: distance.meters, route: route) { result[distance] = time }
        }
        return result
    }

    /// Metres climbed, counting only rises of more than `threshold` metres (so GPS altitude
    /// jitter isn't counted). nil when the run has no altitude.
    public static func elevationGain(route: [RoutePoint], threshold: Double = 3) -> Double? {
        let altitudes = route.compactMap(\.altitude)
        guard altitudes.count >= 2 else { return nil }
        var gain = 0.0
        var low = altitudes[0], high = altitudes[0]
        var climbing = true
        for altitude in altitudes.dropFirst() {
            if climbing {
                if altitude > high { high = altitude }
                else if high - altitude > threshold {
                    gain += max(high - low, 0)
                    climbing = false
                    low = altitude
                }
            } else {
                if altitude < low { low = altitude }
                else if altitude - low > threshold {
                    climbing = true
                    high = altitude
                }
            }
        }
        if climbing { gain += max(high - low, 0) }
        return gain
    }

    /// Altitude through the run as `count` evenly spaced averages (for a small profile chart).
    public static func elevationProfile(route: [RoutePoint], count: Int = 40) -> [Double] {
        let altitudes = route.compactMap(\.altitude)
        guard altitudes.count >= count, count > 0 else { return altitudes }
        let size = Double(altitudes.count) / Double(count)
        return (0..<count).map { index in
            let slice = altitudes[Int(Double(index) * size)..<max(Int(Double(index + 1) * size), Int(Double(index) * size) + 1)]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// Seconds spent in zones 1–5 (index 0 = zone 1); time below zone 1 counts as zone 1.
    public static func secondsInZones(_ samples: [HeartRateSample], zones: HeartRateZones) -> [Double] {
        var seconds = Array(repeating: 0.0, count: 5)
        guard samples.count >= 2 else { return seconds }
        for (previous, next) in zip(samples, samples.dropFirst()) {
            let gap = next.elapsed - previous.elapsed
            guard gap > 0, gap < 60 else { continue }
            let zone = min(max(zones.zone(for: previous.bpm), 1), 5)
            seconds[zone - 1] += gap
        }
        return seconds
    }

    /// Pace (seconds per km) through the run, averaged over windows of `windowSeconds` so GPS
    /// noise doesn't make the chart jagged. Windows with almost no movement are skipped.
    public static func paceSeries(route: [RoutePoint], windowSeconds: Double = 30) -> [RunChartPoint] {
        let cumulative = cumulativeDistances(route)
        guard route.count >= 2, let lastTime = route.last?.elapsed, lastTime > 0 else { return [] }
        var points: [RunChartPoint] = []
        var startIndex = 0
        var windowEnd = windowSeconds
        for index in 1..<route.count where route[index].elapsed >= windowEnd || index == route.count - 1 {
            let time = route[index].elapsed - route[startIndex].elapsed
            let meters = cumulative[index] - cumulative[startIndex]
            if time > 0, meters > 10 {
                let secondsPerKm = time / meters * 1000
                if secondsPerKm < 20 * 60 {
                    points.append(RunChartPoint(elapsed: (route[index].elapsed + route[startIndex].elapsed) / 2, value: secondsPerKm))
                }
            }
            startIndex = index
            windowEnd = route[index].elapsed + windowSeconds
        }
        return points
    }

    /// Heart rate thinned to roughly one point per `windowSeconds`, averaged.
    public static func heartRateSeries(_ samples: [HeartRateSample], windowSeconds: Double = 30) -> [RunChartPoint] {
        guard !samples.isEmpty else { return [] }
        var points: [RunChartPoint] = []
        var bucket: [HeartRateSample] = []
        var bucketEnd = (samples.first?.elapsed ?? 0) + windowSeconds
        func flush() {
            guard !bucket.isEmpty else { return }
            let average = bucket.map(\.bpm).reduce(0, +) / Double(bucket.count)
            let mid = (bucket.first!.elapsed + bucket.last!.elapsed) / 2
            points.append(RunChartPoint(elapsed: mid, value: average))
            bucket = []
        }
        for sample in samples.sorted(by: { $0.elapsed < $1.elapsed }) {
            if sample.elapsed >= bucketEnd {
                flush()
                bucketEnd = sample.elapsed + windowSeconds
            }
            bucket.append(sample)
        }
        flush()
        return points
    }
}

/// A finished run, reduced to what history and totals need.
public struct RunHistoryEntry: Equatable, Sendable {
    public var date: Date
    public var distanceMeters: Double
    public var durationSeconds: Double

    public init(date: Date, distanceMeters: Double, durationSeconds: Double) {
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}

/// Distance, time and count over a period.
public struct RunTotals: Equatable, Sendable {
    public var distanceMeters: Double = 0
    public var durationSeconds: Double = 0
    public var count: Int = 0

    public init(distanceMeters: Double = 0, durationSeconds: Double = 0, count: Int = 0) {
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.count = count
    }

    public var averagePace: Pace? {
        distanceMeters > 50 && durationSeconds > 0 ? Pace(secondsPerKm: durationSeconds / distanceMeters * 1000) : nil
    }
}

/// One bar of the weekly chart.
public struct WeeklyTotal: Equatable, Sendable, Identifiable {
    public var weekStart: Date
    public var actual: Double
    /// Planned value for the week, when a plan covered it.
    public var planned: Double?
    public var id: Date { weekStart }

    public init(weekStart: Date, actual: Double, planned: Double? = nil) {
        self.weekStart = weekStart
        self.actual = actual
        self.planned = planned
    }
}

public enum TrainingHistory {
    public static func totals(_ entries: [RunHistoryEntry], from start: Date, to end: Date) -> RunTotals {
        entries.filter { $0.date >= start && $0.date < end }.reduce(into: RunTotals()) { totals, entry in
            totals.distanceMeters += entry.distanceMeters
            totals.durationSeconds += entry.durationSeconds
            totals.count += 1
        }
    }

    /// Totals for the week, month and year containing `today`.
    public static func periodTotals(_ entries: [RunHistoryEntry], today: Date, calendar: Calendar)
        -> (week: RunTotals, month: RunTotals, year: RunTotals) {
        func range(_ component: Calendar.Component) -> (Date, Date) {
            let start: Date
            if component == .weekOfYear {
                start = calendar.startOfISOWeek(for: today)
            } else {
                start = calendar.dateInterval(of: component, for: today)?.start ?? today
            }
            let end = calendar.date(byAdding: component == .weekOfYear ? .day : component,
                                    value: component == .weekOfYear ? 7 : 1, to: start) ?? today
            return (start, end)
        }
        let week = range(.weekOfYear), month = range(.month), year = range(.year)
        return (totals(entries, from: week.0, to: week.1), totals(entries, from: month.0, to: month.1),
                totals(entries, from: year.0, to: year.1))
    }

    /// The last `weeks` weeks (oldest first) of a value per entry (e.g. distance or volume).
    public static func weekly(_ values: [(date: Date, value: Double)], weeks: Int, today: Date, calendar: Calendar,
                              planned: [Date: Double] = [:]) -> [WeeklyTotal] {
        let thisWeek = calendar.startOfISOWeek(for: today)
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -7 * offset, to: thisWeek),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let actual = values.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.value }
            return WeeklyTotal(weekStart: start, actual: actual, planned: planned[start])
        }
    }
}
