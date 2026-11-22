import Foundation

/// Runs from Apple Health (Apple's Workout app on a GymKit treadmill, a Garmin, another app)
/// that could be a planned run done without Kinetix: same day, not already in Kinetix, and a
/// planned run that day still to do. The app asks before counting it.
public enum HealthRunMatch {
    public struct Planned: Equatable, Sendable {
        public var id: UUID
        public var date: Date
        public var meters: Double?

        public init(id: UUID, date: Date, meters: Double?) {
            self.id = id
            self.date = date
            self.meters = meters
        }
    }

    public struct Suggestion: Equatable, Sendable {
        public var workout: ExternalWorkout
        public var plannedId: UUID
    }

    /// Newest first. A run is offered for one planned run (the closest in distance when there
    /// are two that day), and each planned run for one Health run.
    public static func suggestions(external: [ExternalWorkout], recorded: [DateInterval], planned: [Planned],
                                   dismissed: Set<UUID>, now: Date, calendar: Calendar) -> [Suggestion] {
        let recent = external.filter {
            $0.kind == .run && !dismissed.contains($0.id) && $0.start <= now
                && now.timeIntervalSince($0.start) < 3 * 86_400 && ($0.distanceMeters ?? 0) >= 500
        }
        var taken = Set<UUID>()
        var result: [Suggestion] = []
        for workout in ExternalWorkouts.notRecorded(recent, excluding: recorded).sorted(by: { $0.start > $1.start }) {
            let sameDay = planned.filter { calendar.isDate($0.date, inSameDayAs: workout.start) && !taken.contains($0.id) }
            let distance = workout.distanceMeters ?? 0
            guard let match = sameDay.min(by: { abs(($0.meters ?? distance) - distance) < abs(($1.meters ?? distance) - distance) }) else { continue }
            taken.insert(match.id)
            result.append(Suggestion(workout: workout, plannedId: match.id))
        }
        return result
    }
}
