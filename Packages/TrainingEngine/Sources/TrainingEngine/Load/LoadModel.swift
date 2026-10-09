import Foundation

/// One completed session's load (session RPE: minutes × effort), in arbitrary units (AU).
public struct LoadEntry: Equatable, Sendable {
    public var date: Date
    public var discipline: Discipline
    public var load: Double

    public init(date: Date, discipline: Discipline, load: Double) {
        self.date = date
        self.discipline = discipline
        self.load = load
    }
}

/// Acute:chronic workload ratio zone (traffic light).
public enum LoadStatus: String, Codable, Sendable {
    /// Not enough history yet to judge (first ~2 weeks).
    case building
    /// Ratio below 0.8: doing less than you're used to.
    case undertrained
    /// 0.8–1.3: the "sweet spot".
    case optimal
    /// Above 1.3: a spike in load; injury and illness risk rise.
    case high

    public static let optimalRange: ClosedRange<Double> = 0.8...1.3

    public static func from(ratio: Double?) -> LoadStatus {
        guard let ratio else { return .building }
        if ratio < optimalRange.lowerBound { return .undertrained }
        if ratio > optimalRange.upperBound { return .high }
        return .optimal
    }

    public var title: String {
        switch self {
        case .building: return "Building baseline"
        case .undertrained: return "Undertrained"
        case .optimal: return "Optimal"
        case .high: return "High risk"
        }
    }

    /// One plain-English sentence for the dashboard.
    public var advice: String {
        switch self {
        case .building: return "Keep logging sessions; your load ratio becomes reliable after about two weeks."
        case .undertrained: return "You've done less than usual this week. Fine for a recovery week; otherwise ease back into the plan."
        case .optimal: return "Your recent training matches what your body is used to. A good place to build from."
        case .high: return "This week's load is well above your usual. We've lightened what's coming to keep you healthy."
        }
    }
}

/// Load figures for one discipline (or combined).
public struct LoadFigures: Equatable, Sendable {
    /// Total load over the last 7 days.
    public var acute: Double
    /// Average weekly load over the last 28 days.
    public var chronic: Double
    /// acute / chronic, nil while history is too short.
    public var ratio: Double?
    public var status: LoadStatus { .from(ratio: ratio) }
}

/// Daily totals for charts.
public struct DailyLoad: Equatable, Sendable, Identifiable {
    public var date: Date
    public var running: Double
    public var lifting: Double
    public var other: Double
    public var total: Double { running + lifting + other }
    public var id: Date { date }
}

public struct LoadReport: Equatable, Sendable {
    public var running: LoadFigures
    public var lifting: LoadFigures
    public var combined: LoadFigures
    /// Last 28 days, oldest first (today last).
    public var daily: [DailyLoad]
    /// Combined ratio for each of the last `trendDays` days (nil where history was too short).
    public var ratioTrend: [(date: Date, ratio: Double?)]

    public static func == (lhs: LoadReport, rhs: LoadReport) -> Bool {
        lhs.running == rhs.running && lhs.lifting == rhs.lifting && lhs.combined == rhs.combined && lhs.daily == rhs.daily
            && lhs.ratioTrend.map(\.ratio) == rhs.ratioTrend.map(\.ratio)
    }
}

/// Session-RPE load and the acute:chronic workload ratio (ACWR), using rolling sums:
/// acute = last 7 days' load; chronic = last 28 days' load ÷ 4 (an average week).
/// Running and lifting share one scale because both use minutes × effort.
public enum LoadModel {
    /// Days of history needed before the ratio is shown.
    public static let minimumHistoryDays = 14

    public static func report(entries: [LoadEntry], today: Date, calendar: Calendar, trendDays: Int = 56) -> LoadReport {
        let day = calendar.startOfDay(for: today)
        let firstEntry = entries.map { calendar.startOfDay(for: $0.date) }.min()

        func figures(_ filter: (LoadEntry) -> Bool, asOf end: Date) -> LoadFigures {
            let endNext = calendar.date(byAdding: .day, value: 1, to: end) ?? end
            let start7 = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            let start28 = calendar.date(byAdding: .day, value: -27, to: end) ?? end
            let relevant = entries.filter(filter)
            let acute = relevant.filter { $0.date >= start7 && $0.date < endNext }.reduce(0) { $0 + $1.load }
            let total28 = relevant.filter { $0.date >= start28 && $0.date < endNext }.reduce(0) { $0 + $1.load }
            let chronic = total28 / 4
            var ratio: Double?
            if let firstEntry,
               let days = calendar.dateComponents([.day], from: firstEntry, to: end).day,
               days + 1 >= minimumHistoryDays, chronic > 0 {
                ratio = acute / chronic
            }
            return LoadFigures(acute: acute, chronic: chronic, ratio: ratio)
        }

        let daily: [DailyLoad] = (0..<28).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day),
                  let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            let onDay = entries.filter { $0.date >= date && $0.date < next }
            return DailyLoad(
                date: date,
                running: onDay.filter { $0.discipline == .run }.reduce(0) { $0 + $1.load },
                lifting: onDay.filter { $0.discipline == .strength }.reduce(0) { $0 + $1.load },
                other: onDay.filter { $0.discipline != .run && $0.discipline != .strength }.reduce(0) { $0 + $1.load }
            )
        }

        let trend: [(date: Date, ratio: Double?)] = (0..<trendDays).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day) else { return nil }
            return (date, figures({ _ in true }, asOf: date).ratio)
        }

        return LoadReport(
            running: figures({ $0.discipline == .run }, asOf: day),
            lifting: figures({ $0.discipline == .strength }, asOf: day),
            combined: figures({ _ in true }, asOf: day),
            daily: daily,
            ratioTrend: trend
        )
    }
}

/// Optional daily recovery check-in (each 1–5).
public struct RecoveryCheckIn: Equatable, Sendable {
    /// 1 = terrible sleep, 5 = great.
    public var sleep: Int
    /// 1 = not sore, 5 = very sore.
    public var soreness: Int
    /// 1 = exhausted, 5 = full of energy.
    public var energy: Int

    public init(sleep: Int, soreness: Int, energy: Int) {
        self.sleep = min(max(sleep, 1), 5)
        self.soreness = min(max(soreness, 1), 5)
        self.energy = min(max(energy, 1), 5)
    }

    /// 0…1 readiness (higher is better).
    public var readiness: Double {
        Double((sleep - 1) + (5 - soreness) + (energy - 1)) / 12
    }

    /// Poor recovery: low overall readiness or very sore.
    public var isPoor: Bool { readiness < 0.42 || soreness >= 5 }
}
