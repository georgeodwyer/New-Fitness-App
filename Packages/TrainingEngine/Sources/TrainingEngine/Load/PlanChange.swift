import Foundation

/// A session as it was before or after a change, for the change history.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public var date: Date
    public var slot: SessionSlot
    public var kind: SessionKind
    public var title: String
    public var summary: String
    public var durationMinutes: Double
    /// Planned effort 1–10.
    public var effort: Double
    public var status: SessionStatus
    public var distanceMeters: Double?
    /// Total working sets, for strength sessions.
    public var sets: Int?

    public init(date: Date, slot: SessionSlot, kind: SessionKind, title: String, summary: String, durationMinutes: Double,
                effort: Double, status: SessionStatus, distanceMeters: Double? = nil, sets: Int? = nil) {
        self.date = date
        self.slot = slot
        self.kind = kind
        self.title = title
        self.summary = summary
        self.durationMinutes = durationMinutes
        self.effort = effort
        self.status = status
        self.distanceMeters = distanceMeters
        self.sets = sets
    }

    public init(_ session: WeekSession, zones: PaceZones?) {
        self.init(date: session.date, slot: session.slot, kind: session.kind, title: session.title, summary: session.summary,
                  durationMinutes: session.durationMinutes, effort: session.effort, status: session.status,
                  distanceMeters: zones.flatMap { session.runStructure?.estimate(zones: $0).distanceMeters },
                  sets: session.strength.map { $0.exercises.reduce(0) { $0 + $1.sets } })
    }
}

/// One field that differs between the before and after versions of a session.
public struct FieldChange: Equatable, Sendable, Identifiable {
    public enum Field: String, Sendable, CaseIterable {
        case day, timeOfDay, session, duration, distance, sets, intensity, status
    }

    public var field: Field
    public var label: String
    public var before: String
    public var after: String
    public var id: Field { field }
}

/// A number behind a change ("Load ratio 1.42 · safe up to 1.30").
public struct ChangeTrigger: Codable, Equatable, Sendable, Identifiable {
    public var label: String
    public var value: String
    /// Optional context, e.g. the threshold.
    public var detail: String?
    /// SF Symbol name.
    public var symbol: String

    public init(label: String, value: String, detail: String? = nil, symbol: String) {
        self.label = label
        self.value = value
        self.detail = detail
        self.symbol = symbol
    }

    public var id: String { label }
}

public enum PlanChangeDiff {
    /// What changed between two versions of a session, in display order.
    public static func changes(from before: SessionSnapshot, to after: SessionSnapshot, units: UnitSystem,
                               calendar: Calendar = .kinetix) -> [FieldChange] {
        var result: [FieldChange] = []
        func add(_ field: FieldChange.Field, _ label: String, _ old: String, _ new: String) {
            if old != new { result.append(FieldChange(field: field, label: label, before: old, after: new)) }
        }
        let dayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        add(.day, "Day", before.date.formatted(dayFormat), after.date.formatted(dayFormat))
        add(.timeOfDay, "Time of day", before.slot.displayName, after.slot.displayName)
        add(.session, "Session", before.title, after.title)
        add(.duration, "Duration", minutes(before.durationMinutes), minutes(after.durationMinutes))
        if before.distanceMeters != nil || after.distanceMeters != nil {
            add(.distance, "Distance", distance(before.distanceMeters, units), distance(after.distanceMeters, units))
        }
        if before.sets != nil || after.sets != nil {
            add(.sets, "Working sets", before.sets.map(String.init) ?? "–", after.sets.map(String.init) ?? "–")
        }
        add(.intensity, "Intensity", intensity(before.effort), intensity(after.effort))
        add(.status, "Status", before.status.displayName, after.status.displayName)
        return result
    }

    static func minutes(_ value: Double) -> String { "\(Int(value.rounded())) min" }

    static func distance(_ meters: Double?, _ units: UnitSystem) -> String {
        guard let meters, meters > 0 else { return "–" }
        let value = (Units.distance(meters: meters, in: units) * 10).rounded() / 10
        return "\(value) \(Units.distanceUnitLabel(units))"
    }

    /// Effort 1–10 in words, so small rounding differences don't show as changes.
    static func intensity(_ effort: Double) -> String {
        switch effort {
        case ..<3.5: return "Very easy"
        case ..<5.5: return "Easy"
        case ..<7: return "Moderate"
        case ..<8.5: return "Hard"
        default: return "Very hard"
        }
    }
}

extension SessionSlot {
    public var displayName: String {
        switch self {
        case .morning: return "Morning"
        case .evening: return "Evening"
        }
    }
}

extension SessionStatus {
    public var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .completed: return "Done"
        case .skipped: return "Skipped"
        case .swapped: return "Swapped"
        }
    }
}
