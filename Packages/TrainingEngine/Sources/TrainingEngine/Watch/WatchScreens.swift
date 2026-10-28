import Foundation

// MARK: - What can go on a watch screen

/// A number the runner can put in a slot on a custom watch screen.
public enum WatchMetric: String, Codable, CaseIterable, Sendable, Identifiable {
    // Pace
    case pace, averagePace, lapPace, targetPace, paceVsTarget
    // Heart rate
    case heartRate, heartRateZone, averageHeartRate, timeInZone
    // Workout
    case stepRemaining, nextStep, repProgress, lapTime, lapDistance
    // Extras
    case distance, time, cadence, elevationGain, calories, exertion, timeOfDay

    public var id: String { rawValue }

    public enum Group: String, CaseIterable, Sendable {
        case pace = "Pace", heartRate = "Heart rate", workout = "Workout", extras = "Extras"
    }

    public var group: Group {
        switch self {
        case .pace, .averagePace, .lapPace, .targetPace, .paceVsTarget: return .pace
        case .heartRate, .heartRateZone, .averageHeartRate, .timeInZone: return .heartRate
        case .stepRemaining, .nextStep, .repProgress, .lapTime, .lapDistance: return .workout
        case .distance, .time, .cadence, .elevationGain, .calories, .exertion, .timeOfDay: return .extras
        }
    }

    /// Shown above the number.
    public var label: String {
        switch self {
        case .pace: return "Pace"
        case .averagePace: return "Avg pace"
        case .lapPace: return "Lap pace"
        case .targetPace: return "Target"
        case .paceVsTarget: return "vs target"
        case .heartRate: return "Heart rate"
        case .heartRateZone: return "HR zone"
        case .averageHeartRate: return "Avg HR"
        case .timeInZone: return "In zone"
        case .stepRemaining: return "Step left"
        case .nextStep: return "Next"
        case .repProgress: return "Rep"
        case .lapTime: return "Lap time"
        case .lapDistance: return "Lap dist"
        case .distance: return "Distance"
        case .time: return "Time"
        case .cadence: return "Cadence"
        case .elevationGain: return "Climb"
        case .calories: return "Calories"
        case .exertion: return "Exertion"
        case .timeOfDay: return "Clock"
        }
    }

    /// The name in the phone's picker.
    public var pickerName: String {
        switch self {
        case .pace: return "Pace"
        case .averagePace: return "Average pace"
        case .lapPace: return "Lap pace"
        case .targetPace: return "Target pace"
        case .paceVsTarget: return "Pace vs target"
        case .heartRate: return "Heart rate"
        case .heartRateZone: return "HR zone"
        case .averageHeartRate: return "Average HR"
        case .timeInZone: return "Time in zone"
        case .stepRemaining: return "Step remaining"
        case .nextStep: return "Next step"
        case .repProgress: return "Rep x of y"
        case .lapTime: return "Lap time"
        case .lapDistance: return "Lap distance"
        case .distance: return "Distance"
        case .time: return "Time"
        case .cadence: return "Cadence"
        case .elevationGain: return "Elevation gain"
        case .calories: return "Calories"
        case .exertion: return "Exertion so far"
        case .timeOfDay: return "Time of day"
        }
    }
}

/// How a custom screen is divided up.
public enum WatchLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    /// One number, as large as possible.
    case one
    /// One big number with two below.
    case oneTwo
    /// One big number with a 2 × 2 grid below.
    case oneFour
    /// Three equal rows.
    case threeRows
    /// A 2 × 3 grid.
    case sixSmall

    public var id: String { rawValue }

    public var slotCount: Int {
        switch self {
        case .one: return 1
        case .oneTwo: return 3
        case .oneFour: return 5
        case .threeRows: return 3
        case .sixSmall: return 6
        }
    }

    public var name: String {
        switch self {
        case .one: return "1 big"
        case .oneTwo: return "1 big + 2"
        case .oneFour: return "1 big + 4"
        case .threeRows: return "3 rows"
        case .sixSmall: return "6 small"
        }
    }
}

/// A screen the runner built on their phone.
public struct WatchScreen: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var layout: WatchLayout
    /// One per slot, in reading order. Extra entries are ignored; missing slots show time.
    public var metrics: [WatchMetric]
    public var isOn: Bool

    public init(id: UUID = UUID(), name: String, layout: WatchLayout, metrics: [WatchMetric], isOn: Bool = true) {
        self.id = id
        self.name = name
        self.layout = layout
        self.metrics = metrics
        self.isOn = isOn
    }

    /// Exactly one metric per slot.
    public var slots: [WatchMetric] {
        (0..<layout.slotCount).map { $0 < metrics.count ? metrics[$0] : .time }
    }

    /// Change the layout, keeping the metrics that still fit.
    public mutating func setLayout(_ newLayout: WatchLayout) {
        let fallback: [WatchMetric] = [.pace, .distance, .time, .heartRate, .averagePace, .cadence]
        var kept = Array(metrics.prefix(newLayout.slotCount))
        for metric in fallback where kept.count < newLayout.slotCount && !kept.contains(metric) { kept.append(metric) }
        layout = newLayout
        metrics = kept
    }
}

/// The run pages the runner swipes through, after the controls.
public struct WatchScreenSettings: Codable, Equatable, Sendable {
    /// Structured runs open on the built-in current-rep page.
    public var showRepPage: Bool
    public var screens: [WatchScreen]

    public init(showRepPage: Bool = true, screens: [WatchScreen]) {
        self.showRepPage = showRepPage
        self.screens = screens
    }

    public var enabledScreens: [WatchScreen] { screens.filter(\.isOn) }

    /// Pace & distance and Heart rate on; Laps and Everything ready to switch on.
    public static let standard = WatchScreenSettings(showRepPage: true, screens: [
        WatchScreen(id: UUID(uuidString: "5C1E0A3E-0000-4000-8000-000000000001")!, name: "Pace & distance", layout: .oneFour,
                    metrics: [.pace, .distance, .time, .heartRate, .averagePace]),
        WatchScreen(id: UUID(uuidString: "5C1E0A3E-0000-4000-8000-000000000002")!, name: "Heart rate", layout: .oneTwo,
                    metrics: [.heartRate, .pace, .time]),
        WatchScreen(id: UUID(uuidString: "5C1E0A3E-0000-4000-8000-000000000003")!, name: "Laps", layout: .threeRows,
                    metrics: [.lapPace, .lapDistance, .lapTime], isOn: false),
        WatchScreen(id: UUID(uuidString: "5C1E0A3E-0000-4000-8000-000000000004")!, name: "Everything", layout: .sixSmall,
                    metrics: [.pace, .averagePace, .distance, .time, .heartRate, .cadence], isOn: false),
    ])

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    public static func decode(_ data: Data?) -> WatchScreenSettings? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WatchScreenSettings.self, from: data)
    }
}

// MARK: - Values

/// Everything the watch knows mid-run, to fill in a screen.
public struct WatchMetricInputs: Sendable {
    public var snapshot: RunSnapshot?
    public var structure: RunStructure?
    public var units: UnitSystem
    public var heartRateSamples: [HeartRateSample]
    public var zones: HeartRateZones?
    /// Steps per minute.
    public var cadence: Double?
    public var elevationGainMeters: Double?
    public var calories: Double?
    public var now: Date
    public var calendar: Calendar

    public init(snapshot: RunSnapshot?, structure: RunStructure? = nil, units: UnitSystem, heartRateSamples: [HeartRateSample] = [],
                zones: HeartRateZones? = nil, cadence: Double? = nil, elevationGainMeters: Double? = nil, calories: Double? = nil,
                now: Date = .now, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.structure = structure
        self.units = units
        self.heartRateSamples = heartRateSamples
        self.zones = zones
        self.cadence = cadence
        self.elevationGainMeters = elevationGainMeters
        self.calories = calories
        self.now = now
        self.calendar = calendar
    }
}

/// A slot's number, its unit and how to colour it.
public struct WatchMetricReading: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case plain, good, warning, bad
        /// Heart-rate zone 1–5.
        case zone(Int)
    }

    public var value: String
    public var unit: String
    public var tone: Tone
    /// Heart-rate zone 1–5 for a zone bar under the number.
    public var zone: Int?
    /// Text rather than a number (e.g. the next step): drawn smaller.
    public var isText: Bool

    public init(_ value: String, unit: String = "", tone: Tone = .plain, zone: Int? = nil, isText: Bool = false) {
        self.value = value
        self.unit = unit
        self.tone = tone
        self.zone = zone
        self.isText = isText
    }

    static let empty = WatchMetricReading("–")
}

extension WatchMetric {
    public func reading(_ input: WatchMetricInputs) -> WatchMetricReading {
        let s = input.snapshot
        let units = input.units
        let paceUnit = Units.paceUnitLabel(units)
        let distUnit = Units.distanceUnitLabel(units)
        func pace(_ p: Pace?) -> String { p.map { Units.formatPace($0, units: units) } ?? "–:––" }
        func zoneOf(_ bpm: Double?) -> Int? {
            guard let bpm, let zones = input.zones else { return nil }
            let zone = zones.zone(for: bpm)
            return zone > 0 ? zone : 1
        }

        switch self {
        case .pace:
            let tone: WatchMetricReading.Tone
            switch s?.paceStatus {
            case .onTarget?: tone = .good
            case .tooFast?, .tooSlow?: tone = .warning
            case nil: tone = .plain
            }
            return WatchMetricReading(pace(s?.currentPace), unit: paceUnit, tone: tone)
        case .averagePace:
            return WatchMetricReading(pace(s?.averagePace), unit: paceUnit)
        case .lapPace:
            guard let seconds = s?.lapElapsedSeconds, let meters = s?.lapDistanceMeters, meters > 20 else {
                return WatchMetricReading("–:––", unit: paceUnit)
            }
            return WatchMetricReading(pace(Pace(secondsPerKm: seconds / meters * 1000)), unit: paceUnit)
        case .targetPace:
            guard let target = s?.segment?.targetPace else { return WatchMetricReading("–", isText: true) }
            return WatchMetricReading("\(pace(target.fastest))–\(pace(target.slowest))", unit: paceUnit)
        case .paceVsTarget:
            switch s?.paceStatus {
            case .onTarget?: return WatchMetricReading("On target", tone: .good, isText: true)
            case .tooFast?: return WatchMetricReading("Too fast", tone: .warning, isText: true)
            case .tooSlow?: return WatchMetricReading("Too slow", tone: .warning, isText: true)
            case nil: return WatchMetricReading("No target", isText: true)
            }
        case .heartRate:
            guard let bpm = s?.heartRate else { return WatchMetricReading("–", unit: "bpm") }
            let zone = zoneOf(bpm)
            return WatchMetricReading("\(Int(bpm.rounded()))", unit: "bpm", tone: zone.map { .zone($0) } ?? .plain, zone: zone)
        case .heartRateZone:
            guard let zone = zoneOf(s?.heartRate) else { return WatchMetricReading("–") }
            return WatchMetricReading("Z\(zone)", unit: HeartRateZones.names[zone - 1], tone: .zone(zone), zone: zone)
        case .averageHeartRate:
            let bpms = input.heartRateSamples.map(\.bpm).filter { $0 > 30 && $0 < 250 }
            guard !bpms.isEmpty else { return WatchMetricReading("–", unit: "bpm") }
            return WatchMetricReading("\(Int((bpms.reduce(0, +) / Double(bpms.count)).rounded()))", unit: "bpm")
        case .timeInZone:
            guard let zones = input.zones, let zone = zoneOf(s?.heartRate) else { return WatchMetricReading("–") }
            let minutes = Strain.minutesInZones(samples: input.heartRateSamples, zones: zones)
            let index = min(max(zone, 0), minutes.count - 1)
            return WatchMetricReading(Units.formatMinutesSeconds(minutes[index] * 60), unit: "Z\(zone)", tone: .zone(zone), zone: zone)
        case .stepRemaining:
            guard let remaining = s?.segmentRemaining else { return WatchMetricReading("–") }
            switch remaining {
            case .distance(let meters):
                if units == .metric && meters < 1000 { return WatchMetricReading("\(Int(meters.rounded()))", unit: "m") }
                return WatchMetricReading(String(format: "%.2f", Units.distance(meters: meters, in: units)), unit: distUnit)
            case .duration(let seconds):
                return WatchMetricReading(Units.formatMinutesSeconds(seconds))
            }
        case .nextStep:
            guard let next = s?.nextSegment else { return WatchMetricReading(s?.segment == nil ? "–" : "Finish", isText: true) }
            return WatchMetricReading(next.label ?? next.kind.rawValue.capitalized, isText: true)
        case .repProgress:
            let work = (input.structure?.segments ?? []).enumerated().filter { $0.element.kind == .work }.map(\.offset)
            guard !work.isEmpty, let index = s?.segmentIndex else { return WatchMetricReading("–") }
            let done = work.filter { $0 < index }.count
            let current = work.contains(index) ? done + 1 : done
            return WatchMetricReading("\(max(current, 0))/\(work.count)")
        case .lapTime:
            return WatchMetricReading(Units.formatMinutesSeconds(s?.lapElapsedSeconds ?? s?.elapsedSeconds ?? 0))
        case .lapDistance:
            let meters = s?.lapDistanceMeters ?? s?.distanceMeters ?? 0
            return WatchMetricReading(String(format: "%.2f", Units.distance(meters: meters, in: units)), unit: distUnit)
        case .distance:
            return WatchMetricReading(String(format: "%.2f", Units.distance(meters: s?.distanceMeters ?? 0, in: units)), unit: distUnit)
        case .time:
            return WatchMetricReading(Units.formatMinutesSeconds(s?.elapsedSeconds ?? 0))
        case .cadence:
            return WatchMetricReading(input.cadence.map { "\(Int($0.rounded()))" } ?? "–", unit: "spm")
        case .elevationGain:
            guard let meters = input.elevationGainMeters else { return WatchMetricReading("–", unit: units == .metric ? "m" : "ft") }
            return units == .metric
                ? WatchMetricReading("\(Int(meters.rounded()))", unit: "m")
                : WatchMetricReading("\(Int((meters * 3.28084).rounded()))", unit: "ft")
        case .calories:
            return WatchMetricReading(input.calories.map { "\(Int($0.rounded()))" } ?? "–", unit: "kcal")
        case .exertion:
            guard let zones = input.zones, input.heartRateSamples.count >= 2 else { return WatchMetricReading("–") }
            let strain = Strain.strain(load: Strain.load(samples: input.heartRateSamples, zones: zones))
            return WatchMetricReading("\(Int(strain.rounded()))", unit: "/ 100")
        case .timeOfDay:
            let parts = input.calendar.dateComponents([.hour, .minute], from: input.now)
            return WatchMetricReading(String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0))
        }
    }
}
