import Foundation

/// Personal records for a lift.
public enum RecordKind: String, Codable, CaseIterable, Sendable {
    /// Best estimated one-rep max (Epley) from any set.
    case estimatedOneRepMax
    /// Heaviest weight lifted for at least one rep.
    case heaviestWeight
    /// Most volume (reps × weight) in one session.
    case sessionVolume

    public var displayName: String {
        switch self {
        case .estimatedOneRepMax: return "Estimated 1RM"
        case .heaviestWeight: return "Heaviest weight"
        case .sessionVolume: return "Session volume"
        }
    }
}

public struct PersonalRecord: Equatable, Sendable {
    public var kind: RecordKind
    public var value: Double
    public var previous: Double?
}

public enum PersonalRecords {
    /// Best values in a set of results (completed, weighted sets only).
    public static func bests(in sets: [SetResult]) -> [RecordKind: Double] {
        let weighted = sets.filter { $0.completed && $0.reps > 0 && ($0.weightKg ?? 0) > 0 }
        guard !weighted.isEmpty else { return [:] }
        let e1rm = weighted.map { StrengthMath.estimatedOneRepMax(weightKg: $0.weightKg ?? 0, reps: $0.reps) }.max() ?? 0
        let heaviest = weighted.compactMap(\.weightKg).max() ?? 0
        let volume = weighted.reduce(0) { $0 + Double($1.reps) * ($1.weightKg ?? 0) }
        return [.estimatedOneRepMax: e1rm, .heaviestWeight: heaviest, .sessionVolume: volume]
    }

    /// Records beaten by this session compared with previous bests. A first-ever
    /// session sets records silently (nothing to beat), so it returns none.
    public static func newRecords(sets: [SetResult], previousBests: [RecordKind: Double]) -> [PersonalRecord] {
        guard !previousBests.isEmpty else { return [] }
        return bests(in: sets).compactMap { kind, value in
            guard let previous = previousBests[kind] else { return nil }
            return value > previous + 0.001 ? PersonalRecord(kind: kind, value: value, previous: previous) : nil
        }
        .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }
}

/// Training load and volume helpers shared by both disciplines.
public enum SessionLoad {
    /// Session RPE load: minutes × effort (1-10), in arbitrary units.
    public static func srpe(durationSeconds: Double, effort: Double) -> Double {
        max(0, durationSeconds / 60) * min(max(effort, 0), 10)
    }

    /// Lifting volume: Σ reps × weight (kg).
    public static func volumeKg(_ sets: [SetResult]) -> Double {
        sets.filter(\.completed).reduce(0) { $0 + Double($1.reps) * ($1.weightKg ?? 0) }
    }
}
