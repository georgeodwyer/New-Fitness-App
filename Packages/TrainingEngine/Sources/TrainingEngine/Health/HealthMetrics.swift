import Foundation

/// A body measurement read from Apple Health (or any wearable that writes to it, e.g. Whoop).
public enum HealthMetric: String, Codable, CaseIterable, Sendable {
    case restingHeartRate, hrv, sleep, steps, activeEnergy, vo2Max, respiratoryRate

    public var displayName: String {
        switch self {
        case .restingHeartRate: return "Resting HR"
        case .hrv: return "HRV"
        case .sleep: return "Sleep"
        case .steps: return "Steps"
        case .activeEnergy: return "Active energy"
        case .vo2Max: return "VO\u{2082} max"
        case .respiratoryRate: return "Breathing rate"
        }
    }

    public var unit: String {
        switch self {
        case .restingHeartRate: return "bpm"
        case .hrv: return "ms"
        case .sleep: return "h"
        case .steps: return "steps"
        case .activeEnergy: return "kcal"
        case .vo2Max: return "ml/kg/min"
        case .respiratoryRate: return "breaths/min"
        }
    }

    public var symbol: String {
        switch self {
        case .restingHeartRate: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .sleep: return "bed.double.fill"
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame.fill"
        case .vo2Max: return "lungs.fill"
        case .respiratoryRate: return "wind"
        }
    }

    /// Daily totals (shown as bars) rather than one reading a day (shown as a line).
    public var isDailyTotal: Bool { self == .steps || self == .activeEnergy || self == .sleep }

    /// Which way is good. nil when neither direction is better day to day.
    public var higherIsBetter: Bool? {
        switch self {
        case .restingHeartRate: return false
        case .hrv, .sleep, .vo2Max: return true
        case .steps, .activeEnergy, .respiratoryRate: return nil
        }
    }

    /// Plain-English explanation for the detail screen.
    public var explanation: String {
        switch self {
        case .restingHeartRate:
            return "Your heart rate at complete rest, usually measured overnight. It drops as you get fitter. A morning reading several beats above your usual can mean fatigue, illness, stress, alcohol or poor sleep, so Kinetix uses it as a recovery signal."
        case .hrv:
            return "Heart rate variability: the small changes in time between heartbeats, measured overnight. Higher than your usual generally means you're well recovered; well below it can mean you're tired, stressed or getting ill. Compare it only with your own numbers: it varies a lot between people and devices."
        case .sleep:
            return "Time asleep last night. Most adults who train need 7–9 hours. Sleep is when training adaptations happen, so a run of short nights is worth taking seriously."
        case .steps:
            return "All steps counted by your phone or watch, including runs. Useful as a picture of how active your days are outside training."
        case .activeEnergy:
            return "Calories burned through movement, on top of what your body uses at rest. It includes your training sessions."
        case .vo2Max:
            return "An estimate of the most oxygen your body can use, from your Apple Watch's outdoor walks and runs. It rises slowly with consistent aerobic training: a good long-term fitness marker, not a day-to-day one."
        case .respiratoryRate:
            return "Breaths per minute while asleep. It's normally very steady, so a clear rise above your usual can be an early sign of illness."
        }
    }

    /// 12345 → "12,345".
    static func grouped(_ number: Int) -> String {
        let digits = String(abs(number))
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return (number < 0 ? "-" : "") + result
    }

    /// The value as shown, e.g. "52", "7 h 20 m", "8,412".
    public func format(_ value: Double) -> String {
        switch self {
        case .sleep:
            let minutes = Int((value * 60).rounded())
            return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) m"
        case .steps, .activeEnergy:
            return Self.grouped(Int(value.rounded()))
        case .vo2Max, .respiratoryRate:
            return String(format: "%.1f", value)
        case .restingHeartRate, .hrv:
            return "\(Int(value.rounded()))"
        }
    }
}

/// One day's value of a metric.
public struct HealthDay: Codable, Equatable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// The latest value of a metric compared with the person's usual.
public struct HealthTrend: Equatable, Sendable {
    public enum Direction: Equatable, Sendable { case up, down, steady }

    public var metric: HealthMetric
    public var latest: HealthDay
    /// Median of the 30 days before the latest reading (nil with fewer than 5 readings).
    public var usual: Double?
    public var average7: Double?
    public var average30: Double?

    /// Change of the latest value against usual, as a fraction (0.1 = 10% higher).
    public var change: Double? {
        guard let usual, usual != 0 else { return nil }
        return (latest.value - usual) / usual
    }

    /// Within ±5% (or ±2 for heart rates) of usual counts as steady.
    public var direction: Direction {
        guard let usual else { return .steady }
        let difference = latest.value - usual
        let threshold = metric == .restingHeartRate ? 2 : abs(usual) * 0.05
        if abs(difference) < threshold { return .steady }
        return difference > 0 ? .up : .down
    }

    /// True when the change is the good way, false the bad way, nil when neutral/steady.
    public var isGoodChange: Bool? {
        guard direction != .steady, let higherIsBetter = metric.higherIsBetter else { return nil }
        return (direction == .up) == higherIsBetter
    }

    /// "6% above your usual", "3 bpm below your usual", "about your usual".
    public var comparisonText: String? {
        guard let usual else { return nil }
        if direction == .steady { return "about your usual" }
        let side = direction == .up ? "above" : "below"
        switch metric {
        case .restingHeartRate:
            return "\(Int(abs(latest.value - usual).rounded())) bpm \(side) your usual"
        case .sleep:
            return "\(metric.format(abs(latest.value - usual))) \(side) your usual"
        default:
            return "\(Int((abs(change ?? 0) * 100).rounded()))% \(side) your usual"
        }
    }

    /// Builds the trend from daily values (any order). nil when there are none.
    public static func make(metric: HealthMetric, days: [HealthDay], calendar: Calendar = .current) -> HealthTrend? {
        let sorted = days.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }
        let before = sorted.dropLast().filter { latest.date.timeIntervalSince($0.date) <= 31 * 86_400 }.map(\.value)
        let usual = before.count >= 5 ? median(before) : nil
        func average(lastDays count: Int) -> Double? {
            guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: latest.date)) else { return nil }
            let values = sorted.filter { $0.date >= start }.map(\.value)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return HealthTrend(metric: metric, latest: latest, usual: usual, average7: average(lastDays: 7), average30: average(lastDays: 30))
    }

    public static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Days in a chart window, oldest first (missing days are left out, not zero-filled).
public enum HealthSeries {
    public static func window(_ days: [HealthDay], lastDays count: Int, endingOn end: Date, calendar: Calendar = .current) -> [HealthDay] {
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: calendar.startOfDay(for: end)) else { return [] }
        return days.filter { $0.date >= start && $0.date <= end }.sorted { $0.date < $1.date }
    }
}

// MARK: - Recovery signals

/// Compares last night's HRV with the person's usual. HRV well below usual is a common sign
/// of fatigue, stress or illness: used like a raised resting heart rate, as one recovery
/// signal alongside the check-in (on its own, one low reading is often noise).
public struct HRVSignal: Equatable, Sendable {
    public var today: Double
    /// Median of the previous readings.
    public var baseline: Double
    /// Average of the last few nights including last night (smooths one-night swings), and how
    /// many nights it covers. With one night it's just last night.
    public var recentAverage: Double
    public var recentNights: Int

    public init(today: Double, baseline: Double, recentAverage: Double? = nil, recentNights: Int = 1) {
        self.today = today
        self.baseline = baseline
        self.recentAverage = recentAverage ?? today
        self.recentNights = recentAverage == nil ? 1 : max(1, recentNights)
    }

    /// Last night against usual as a fraction (-0.2 = 20% lower).
    public var change: Double { baseline > 0 ? (today - baseline) / baseline : 0 }

    /// The recent average against usual (used for the recovery score).
    public var recentChange: Double { baseline > 0 ? (recentAverage - baseline) / baseline : 0 }

    /// "3-night average 58 ms · 6% below your usual 62 ms"
    public var recentDescription: String {
        let percent = Int((abs(recentChange) * 100).rounded())
        let comparison = percent == 0 ? "same as your usual" : "\(percent)% \(recentChange > 0 ? "above" : "below") your usual"
        let label = recentNights > 1 ? "\(recentNights)-night average " : "Last night "
        return label + "\(Int(recentAverage.rounded())) ms · \(comparison) \(Int(baseline.rounded())) ms"
    }

    /// At least `BalanceRules.recovery.hrvSuppressedPercent` below usual.
    public var isSuppressed: Bool { change <= -BalanceRules.current.recovery.hrvSuppressedPercent / 100 }

    /// `history` is the previous days' readings (most recent ~4 weeks), not including today.
    /// `recent` is the nights just before last night to average with it (e.g. the two before).
    public static func assess(today: Double, history: [Double], recent: [Double] = []) -> HRVSignal? {
        let usable = history.filter { $0 > 5 && $0 < 300 }
        guard usable.count >= BalanceRules.current.recovery.hrvMinimumReadings, today > 5, today < 300 else { return nil }
        let nights = [today] + recent.filter { $0 > 5 && $0 < 300 }
        return HRVSignal(today: today, baseline: HealthTrend.median(usable),
                         recentAverage: nights.count > 1 ? nights.reduce(0, +) / Double(nights.count) : nil,
                         recentNights: nights.count)
    }

    /// "48 ms · 18% below your usual"
    public var description: String {
        let percent = Int((abs(change) * 100).rounded())
        let comparison = percent == 0 ? "same as your usual" : "\(percent)% \(change > 0 ? "above" : "below") your usual"
        return "\(Int(today.rounded())) ms · \(comparison)"
    }
}

/// One "asleep" record from Apple Health (a sleep stage, or plain "asleep").
public struct SleepSample: Equatable, Sendable {
    /// The app or device that recorded it.
    public var source: String
    public var start: Date
    public var end: Date

    public init(source: String, start: Date, end: Date) {
        self.source = source
        self.start = start
        self.end = max(start, end)
    }
}

/// Hours asleep per night.
public enum SleepNights {
    /// A night runs from 6 pm to 6 pm and counts on the day you woke up, so sleep before
    /// midnight belongs to the same night as sleep after it. Overlapping records from one
    /// source are merged (no double counting); when several sources recorded the night
    /// (say an Apple Watch and a Whoop), the longest is used. Nights under 30 minutes are dropped.
    public static func days(_ samples: [SleepSample], calendar: Calendar) -> [HealthDay] {
        var bySourceNight: [String: [Date: [SleepSample]]] = [:]
        for sample in samples where sample.end > sample.start {
            let night = calendar.startOfDay(for: sample.end.addingTimeInterval(6 * 3600))
            bySourceNight[sample.source, default: [:]][night, default: []].append(sample)
        }
        var best: [Date: Double] = [:]
        for nights in bySourceNight.values {
            for (night, records) in nights {
                let hours = mergedSeconds(records) / 3600
                best[night] = max(best[night] ?? 0, hours)
            }
        }
        return best.filter { $0.value >= 0.5 }.map { HealthDay(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }

    /// Total time covered by the records, counting overlaps once.
    static func mergedSeconds(_ records: [SleepSample]) -> Double {
        let sorted = records.sorted { $0.start < $1.start }
        var total = 0.0
        var current: (start: Date, end: Date)?
        for record in sorted {
            if let open = current, record.start <= open.end {
                current = (open.start, max(open.end, record.end))
            } else {
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                current = (record.start, record.end)
            }
        }
        if let open = current { total += open.end.timeIntervalSince(open.start) }
        return total
    }
}

/// Suggests a 1–5 check-in sleep score from hours asleep.
public enum SleepScore {
    public static func score(hours: Double) -> Int {
        switch hours {
        case ..<5: return 1
        case ..<6: return 2
        case ..<7: return 3
        case ..<8: return 4
        default: return 5
        }
    }
}

// MARK: - Dashboard layout

/// The cards on the dashboard that can be moved or hidden.
public enum DashboardCard: String, Codable, CaseIterable, Sendable {
    case today, checkIn, body, load, dailyLoad, week, weekStrip, goal, records

    public static let defaultOrder: [DashboardCard] = [.load, .today, .weekStrip, .checkIn, .dailyLoad, .week, .body, .goal, .records]

    public var displayName: String {
        switch self {
        case .today: return "Today's sessions"
        case .checkIn: return "Your score"
        case .body: return "Body (Apple Health)"
        case .load: return "Exertion and recovery"
        case .dailyLoad: return "Daily exertion chart"
        case .week: return "This week vs plan"
        case .weekStrip: return "Week at a glance"
        case .goal: return "Goal progress"
        case .records: return "Records and race estimates"
        }
    }

    public var symbol: String {
        switch self {
        case .today: return "calendar"
        case .checkIn: return "sun.horizon"
        case .body: return "heart.text.square"
        case .load: return "gauge.with.dots.needle.50percent"
        case .dailyLoad: return "chart.bar"
        case .week: return "checklist"
        case .weekStrip: return "calendar.day.timeline.left"
        case .goal: return "flag.checkered"
        case .records: return "trophy"
        }
    }
}

/// The person's dashboard order and hidden cards. Stored as raw strings so a layout saved by
/// a newer or older version of the app still loads: unknown cards are dropped, new ones added.
public struct DashboardLayout: Codable, Equatable, Sendable {
    public var order: [String]
    public var hidden: [String]

    public init(order: [DashboardCard] = DashboardCard.defaultOrder, hidden: Set<DashboardCard> = []) {
        self.order = order.map(\.rawValue)
        self.hidden = hidden.map(\.rawValue).sorted()
    }

    /// A new dashboard shows every card; any can be hidden in Edit dashboard.
    public static let defaultHidden: Set<DashboardCard> = []

    public static let `default` = DashboardLayout(hidden: defaultHidden)

    /// Every known card once, in the saved order; cards the saved layout didn't know about go
    /// where they sit in the default order.
    public var cards: [DashboardCard] {
        var result: [DashboardCard] = []
        for raw in order {
            if let card = DashboardCard(rawValue: raw), !result.contains(card) { result.append(card) }
        }
        for (index, card) in DashboardCard.defaultOrder.enumerated() where !result.contains(card) {
            // After the card that precedes it by default, if present.
            let previous = DashboardCard.defaultOrder[..<index].last { result.contains($0) }
            let position = previous.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(card, at: position)
        }
        return result
    }

    public var hiddenCards: Set<DashboardCard> { Set(hidden.compactMap(DashboardCard.init(rawValue:))) }

    /// The cards to show, in order.
    public var visibleCards: [DashboardCard] { cards.filter { !hiddenCards.contains($0) } }

    public func isHidden(_ card: DashboardCard) -> Bool { hiddenCards.contains(card) }

    public mutating func setHidden(_ card: DashboardCard, _ isHidden: Bool) {
        var set = hiddenCards
        if isHidden { set.insert(card) } else { set.remove(card) }
        hidden = set.map(\.rawValue).sorted()
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var cards = self.cards
        let moving = source.sorted().map { cards[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { cards.remove(at: index) }
        cards.insert(contentsOf: moving, at: min(max(insertAt, 0), cards.count))
        order = cards.map(\.rawValue)
    }
}

/// Readings taken overnight (8 pm the evening before to 10 am), one average per morning.
/// Daytime readings (HRV especially) move with activity, coffee and stress, so leaving them
/// out keeps the morning's figure settled for the rest of the day.
public enum OvernightReadings {
    public static func days(_ readings: [(date: Date, value: Double)], calendar: Calendar) -> [HealthDay] {
        var byDay: [Date: [Double]] = [:]
        for reading in readings where reading.value > 0 {
            let hour = calendar.component(.hour, from: reading.date)
            let day: Date
            if hour < 10 {
                day = calendar.startOfDay(for: reading.date)
            } else if hour >= 20, let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reading.date)) {
                day = next
            } else {
                continue
            }
            byDay[day, default: []].append(reading.value)
        }
        return byDay.map { HealthDay(date: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }
}
