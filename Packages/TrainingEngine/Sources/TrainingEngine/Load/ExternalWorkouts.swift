import Foundation

/// A workout recorded by another app (e.g. Apple Watch Workout), read from Apple Health.
public struct ExternalWorkout: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case run, strength, cycling, walking, other
    }

    public var id: UUID
    public var start: Date
    public var end: Date
    public var kind: Kind
    public var name: String
    public var distanceMeters: Double?
    public var averageHeartRate: Double?

    public init(id: UUID, start: Date, end: Date, kind: Kind, name: String, distanceMeters: Double? = nil, averageHeartRate: Double? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.name = name
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
    }

    public var durationSeconds: Double { max(0, end.timeIntervalSince(start)) }

    public var discipline: Discipline {
        switch kind {
        case .run: return .run
        case .strength: return .strength
        case .cycling, .walking, .other: return .crossTraining
        }
    }

    /// Effort isn't known for other apps' workouts, so it's estimated: from average heart
    /// rate as a share of max HR when both are known, else a typical value per activity.
    public func estimatedEffort(maxHeartRate: Double?) -> Double {
        if let hr = averageHeartRate, let max = maxHeartRate, max > 0 {
            // ~60% HRmax feels like 3/10, ~95% like 9/10.
            let fraction = hr / max
            return min(10, Swift.max(1, ((fraction - 0.5) / 0.45 * 8 + 1).rounded()))
        }
        switch kind {
        case .run: return 5
        case .strength: return 6
        case .cycling: return 4
        case .walking: return 2
        case .other: return 4
        }
    }
}

public enum ExternalWorkouts {
    /// Load entries for workouts from other apps, leaving out any that overlap a session
    /// Kinetix already recorded (e.g. a run tracked on both the Watch and the iPhone), so
    /// the same training isn't counted twice.
    public static func loadEntries(_ workouts: [ExternalWorkout], excluding recorded: [DateInterval],
                                   maxHeartRate: Double? = nil) -> [LoadEntry] {
        workouts.compactMap { workout in
            guard workout.durationSeconds >= 5 * 60 else { return nil }
            let interval = DateInterval(start: workout.start, end: max(workout.start, workout.end))
            let overlapsRecorded = recorded.contains { other in
                guard let overlap = interval.intersection(with: other) else { return false }
                let shorter = min(interval.duration, other.duration)
                return shorter > 0 && overlap.duration / shorter >= 0.5
            }
            guard !overlapsRecorded else { return nil }
            let effort = workout.estimatedEffort(maxHeartRate: maxHeartRate)
            return LoadEntry(date: workout.start, discipline: workout.discipline,
                             load: SessionLoad.srpe(durationSeconds: workout.durationSeconds, effort: effort))
        }
    }
}
