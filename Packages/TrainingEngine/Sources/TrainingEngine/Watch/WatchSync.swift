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

/// What the watch's hands-free gestures do during a run (set on the iPhone).
public struct WatchControlSettings: Codable, Equatable, Sendable {
    public enum Action: String, Codable, CaseIterable, Sendable {
        case off
        /// Skips to the next step of a session, or marks a lap when there are no steps.
        case nextOrLap
        case pauseResume

        public var displayName: String {
            switch self {
            case .off: return "Off"
            case .nextOrLap: return "Next step / lap"
            case .pauseResume: return "Pause / resume"
            }
        }
    }

    /// Double tap (finger and thumb), on watches that support it.
    public var doubleTap: Action
    /// A firm turn of the Digital Crown, on any watch.
    public var crown: Action
    /// How far the crown must turn in one go (in full turns): 0.25 or 0.5.
    public var crownTurn: Double
    /// Seconds an "Undo" shows after a gesture skips, laps or pauses.
    public var undoSeconds: Double
    /// How easily the crown triggers, 1 (needs a big, quick turn) to 5 (a quarter turn).
    /// Lower levels stop a sleeve brushing the crown from skipping steps. Nil in settings
    /// saved before this existed (treated as 3).
    public var crownSensitivity: Int?
    /// Steps of a session move on by themselves when they're done (nil = yes). Off: the
    /// watch buzzes and waits for Next step (double tap, crown or the button).
    public var autoNextStep: Bool? = nil
    public var movesToNextStepAutomatically: Bool { autoNextStep ?? true }

    public init(doubleTap: Action = .nextOrLap, crown: Action = .nextOrLap, crownTurn: Double = 0.25, undoSeconds: Double = 3,
                crownSensitivity: Int? = 3) {
        self.doubleTap = doubleTap
        self.crown = crown
        self.crownTurn = crownTurn
        self.undoSeconds = undoSeconds
        self.crownSensitivity = crownSensitivity
    }

    public static let sensitivityRange = 1...5

    /// The sensitivity in use (1–5).
    public var sensitivity: Int { min(max(crownSensitivity ?? 3, 1), 5) }

    /// How far the crown must turn (in full turns) for the current sensitivity. Even the most
    /// sensitive needs a full turn, so a brush against a sleeve never counts.
    public var crownTurnsNeeded: Double {
        switch sensitivity {
        case 1: return 2.0
        case 2: return 1.75
        case 3: return 1.5
        case 4: return 1.25
        default: return 1.0
        }
    }

    /// The turn must be done within this many seconds: a slow drag (like a sleeve rubbing)
    /// never adds up to a trigger. Bigger turns get a little longer.
    public var crownWindowSeconds: Double {
        switch sensitivity {
        case 1: return 1.2
        case 2: return 1.05
        case 3: return 0.9
        case 4: return 0.75
        default: return 0.6
        }
    }

    /// "Two full turns, quickly", for Settings.
    public static func sensitivityDescription(_ level: Int) -> String {
        switch level {
        case 1: return "Least sensitive: two full, quick turns"
        case 2: return "One and three-quarter turns, quickly"
        case 3: return "One and a half turns, quickly"
        case 4: return "One and a quarter turns, quickly"
        default: return "Most sensitive: one full, quick turn"
        }
    }

    public static let standard = WatchControlSettings()

    /// Watch models with double tap: Series 9 and later, Ultra 2 and later, SE (3rd gen)
    /// (all "Watch7,x" or newer). `machine` is the hardware identifier, e.g. "Watch7,3".
    public static func supportsDoubleTap(machine: String) -> Bool {
        guard machine.hasPrefix("Watch"), let major = Int(machine.dropFirst(5).prefix { $0.isNumber }) else { return false }
        return major >= 7
    }
}

/// What the watch tells the phone about itself (so Settings only offers what it supports).
public struct WatchDeviceInfo: Codable, Equatable, Sendable {
    public var machine: String
    public var supportsDoubleTap: Bool

    public init(machine: String, supportsDoubleTap: Bool) {
        self.machine = machine
        self.supportsDoubleTap = supportsDoubleTap
    }

    public func encoded() -> Data { (try? WatchCoding.encoder.encode(self)) ?? Data() }
    public static func decode(_ data: Data) -> WatchDeviceInfo? { try? WatchCoding.decoder.decode(WatchDeviceInfo.self, from: data) }
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
    /// Gesture settings (nil from older phones: the watch uses the standard settings).
    public var controls: WatchControlSettings?
    /// The runner's custom run screens (nil from older phones: the standard set).
    public var screens: WatchScreenSettings?
    /// Heart-rate zone starts (bpm, zones 1–5) and max, for zone colours and exertion.
    public var zoneStarts: [Double]?
    public var maxHeartRate: Double?

    public init(generatedAt: Date, units: UnitSystem, coaching: CoachingConfig, runs: [WatchRunOption],
                controls: WatchControlSettings? = nil, screens: WatchScreenSettings? = nil,
                zoneStarts: [Double]? = nil, maxHeartRate: Double? = nil) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.units = units
        self.coaching = coaching
        self.runs = runs
        self.controls = controls
        self.screens = screens
        self.zoneStarts = zoneStarts
        self.maxHeartRate = maxHeartRate
    }

    /// The runner's zones, when the phone sent them.
    public var heartRateZones: HeartRateZones? {
        guard let starts = zoneStarts, starts.count == 5, let max = maxHeartRate else { return nil }
        return HeartRateZones(maxHeartRate: max, maxSource: .custom, starts: starts, isCustom: false)
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
