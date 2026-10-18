import Foundation

// What the iPhone and Apple Watch send each other. The phone sends a `WatchPlan` (the runs
// the watch can start, plus settings) whenever it changes; the watch sends back a
// `WatchRunResult` for each finished run. Both are plain JSON; new fields must be optional
// so a watch and phone on different app versions still understand each other.

/// A run the watch can start.
public struct WatchRunOption: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// A session from the training plan (`id` is the planned session's id).
        case planned
        /// A saved workout from the Record tab (`id` is the template's id).
        case template
        /// A free run with no targets.
        case free
    }

    public var id: UUID
    public var source: Source
    public var title: String
    /// e.g. "6 × 400 m at 5K pace".
    public var detail: String
    /// The day a planned session is due.
    public var date: Date?
    public var structure: RunStructure?
    /// `RecordRunType` raw value for Record-tab runs.
    public var recordType: String?
    /// Pre-selected answer for "How hard was that?".
    public var typicalEffort: Double

    public init(id: UUID, source: Source, title: String, detail: String = "", date: Date? = nil, structure: RunStructure? = nil,
                recordType: String? = nil, typicalEffort: Double = 5) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.date = date
        self.structure = structure
        self.recordType = recordType
        self.typicalEffort = typicalEffort
    }

    /// The always-available free run (the same id every time, so it's never confused with a plan session).
    public static let freeRun = WatchRunOption(id: UUID(uuidString: "00000000-0000-0000-0000-00000000F4EE")!, source: .free,
                                               title: "Free run", detail: "No targets, splits only", recordType: "free")
}

/// Everything the watch needs to train without the phone.
public struct WatchPlan: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var units: UnitSystem
    public var coaching: CoachingConfig
    /// Planned runs still to do (today first), then saved workouts.
    public var runs: [WatchRunOption]

    public init(generatedAt: Date, units: UnitSystem, coaching: CoachingConfig, runs: [WatchRunOption]) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.units = units
        self.coaching = coaching
        self.runs = runs
    }

    public static let empty = WatchPlan(generatedAt: .distantPast, units: .metric, coaching: CoachingConfig(), runs: [])

    public func encoded() -> Data { (try? WatchCoding.encoder.encode(self)) ?? Data() }
    public static func decode(_ data: Data) -> WatchPlan? { try? WatchCoding.decoder.decode(WatchPlan.self, from: data) }

    /// Planned runs due today (or overdue from earlier today's list).
    public func planned(on day: Date, calendar: Calendar) -> [WatchRunOption] {
        runs.filter { $0.source == .planned && $0.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }

    /// Planned runs after today, in date order.
    public func upcoming(after day: Date, calendar: Calendar) -> [WatchRunOption] {
        let end = calendar.startOfDay(for: day).addingTimeInterval(86_400)
        return runs.filter { $0.source == .planned && ($0.date ?? .distantPast) >= end }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    public var templates: [WatchRunOption] { runs.filter { $0.source == .template } }
}

/// A run finished on the watch, sent to the phone to save.
public struct WatchRunResult: Codable, Equatable, Identifiable, Sendable {
    /// Also used as the saved run's id, so a result delivered twice is only saved once.
    public var id: UUID
    public var option: WatchRunOption
    public var startedAt: Date
    public var finishedAt: Date
    public var summary: RunSummary
    public var effort: Double
    /// The workout the watch saved to Apple Health (so the phone doesn't save it again).
    public var healthKitWorkoutId: UUID?

    public init(id: UUID = UUID(), option: WatchRunOption, startedAt: Date, finishedAt: Date, summary: RunSummary, effort: Double,
                healthKitWorkoutId: UUID? = nil) {
        self.id = id
        self.option = option
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.effort = effort
        self.healthKitWorkoutId = healthKitWorkoutId
    }

    public func encoded() -> Data { (try? WatchCoding.encoder.encode(self)) ?? Data() }
    public static func decode(_ data: Data) -> WatchRunResult? { try? WatchCoding.decoder.decode(WatchRunResult.self, from: data) }

    /// Keeps at most one route point every `seconds` (the watch records about one a second),
    /// so long runs stay small enough to send.
    public func thinned(everySeconds seconds: Double = 3) -> WatchRunResult {
        var copy = self
        var kept: [RoutePoint] = []
        for point in summary.route {
            if let last = kept.last, point.elapsed - last.elapsed < seconds { continue }
            kept.append(point)
        }
        if let last = summary.route.last, kept.last != last { kept.append(last) }
        copy.summary.route = kept
        return copy
    }
}

enum WatchCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
