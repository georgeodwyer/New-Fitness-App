import Foundation

// MARK: - Exercise library groupings

/// The main muscle group an exercise trains, used to filter the exercise picker.
public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest, back, shoulders, arms, legs, glutes, core, fullBody

    /// Works out the group from a movement pattern in the exercise library.
    public init(pattern: String) {
        switch pattern {
        case "horizontalPush": self = .chest
        case "horizontalPull", "verticalPull": self = .back
        case "verticalPush": self = .shoulders
        case "arms": self = .arms
        case "squat", "lunge", "calf": self = .legs
        case "hinge", "hingeAccessory": self = .glutes
        case "core", "antiRotation": self = .core
        default: self = .fullBody
        }
    }

    public var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .legs: return "Legs"
        case .glutes: return "Glutes & hamstrings"
        case .core: return "Core"
        case .fullBody: return "Full body"
        }
    }
}

extension ExerciseLoading: CaseIterable {
    public static var allCases: [ExerciseLoading] { [.barbell, .dumbbell, .machine, .bodyweight] }

    public var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .dumbbell: return "Dumbbell"
        case .machine: return "Machine / cable"
        case .bodyweight: return "Bodyweight"
        }
    }
}

public enum ExerciseSearch {
    /// Exercises matching the search text and filters, alphabetically.
    public static func filter(_ exercises: [ExerciseDefinition], query: String = "", muscle: MuscleGroup? = nil,
                              loading: ExerciseLoading? = nil) -> [ExerciseDefinition] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        var seenNames = Set<String>()
        return exercises
            .filter { exercise in
                let name = exercise.name.lowercased()
                return words.allSatisfy { name.contains($0) }
                    && (muscle == nil || exercise.muscleGroup == muscle)
                    && (loading == nil || exercise.loading == loading)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            // The plan library has a couple of exercises listed twice under different patterns.
            .filter { seenNames.insert($0.name.lowercased()).inserted }
    }
}

// MARK: - Gym templates

/// One exercise in a saved gym workout ("Push day"): how many sets, the rep range and rest.
public struct GymTemplateItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var exerciseId: String
    public var name: String
    public var sets: Int
    public var repsLow: Int
    public var repsHigh: Int
    public var restSeconds: Int
    public var isBodyweight: Bool

    public init(id: UUID = UUID(), exerciseId: String, name: String, sets: Int = 3, repsLow: Int = 8, repsHigh: Int = 12,
                restSeconds: Int = 90, isBodyweight: Bool = false) {
        self.id = id
        self.exerciseId = exerciseId
        self.name = name
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.restSeconds = restSeconds
        self.isBodyweight = isBodyweight
    }

    /// Sensible starting values for an exercise added to a workout.
    public static func starter(for exercise: ExerciseDefinition) -> GymTemplateItem {
        let heavy = exercise.mainLift != nil
        let core = exercise.muscleGroup == .core
        return GymTemplateItem(
            exerciseId: exercise.id,
            name: exercise.name,
            sets: 3,
            repsLow: heavy ? 5 : (core ? 10 : 8),
            repsHigh: heavy ? 8 : (core ? 15 : 12),
            restSeconds: heavy ? 150 : (core ? 45 : 90),
            isBodyweight: exercise.loading == .bodyweight
        )
    }

    /// "3 × 8–12", or "3 × 10" when the range is a single number.
    public var setsAndReps: String {
        repsLow == repsHigh ? "\(sets) × \(repsLow)" : "\(sets) × \(repsLow)–\(repsHigh)"
    }
}

public enum GymTemplate {
    /// A rough duration: about 45 s per set plus the rest after it, plus 5 minutes to set up.
    public static func estimatedMinutes(_ items: [GymTemplateItem]) -> Int {
        let seconds = items.reduce(0.0) { $0 + Double($1.sets) * (45 + Double($1.restSeconds)) }
        return Int((seconds / 60 + 5).rounded())
    }

    /// "5 exercises · 16 sets · about 55 min".
    public static func summary(_ items: [GymTemplateItem]) -> String {
        let sets = items.reduce(0) { $0 + $1.sets }
        let exercises = items.count == 1 ? "1 exercise" : "\(items.count) exercises"
        return "\(exercises) · \(sets) set\(sets == 1 ? "" : "s") · about \(estimatedMinutes(items)) min"
    }
}

// MARK: - Pre-fill from last time

/// A set done in an earlier workout.
public struct PreviousSet: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// Starting weight and reps for one set of a new workout.
public struct PrefilledSet: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int
}

public enum GymPrefill {
    /// Progression key for sets logged outside the plan, so they never move plan weights.
    public static func freeKey(exerciseId: String) -> String { "\(exerciseId).free" }

    /// Each set copies the same set from last time (or the last one, if there are now more
    /// sets). With no history, uses the library's default weight and the top of the rep range.
    public static func sets(for item: GymTemplateItem, previous: [PreviousSet], defaultWeightKg: Double?) -> [PrefilledSet] {
        (0..<max(item.sets, 0)).map { index in
            if !previous.isEmpty {
                let last = previous[min(index, previous.count - 1)]
                return PrefilledSet(weightKg: item.isBodyweight ? 0 : last.weightKg, reps: last.reps)
            }
            return PrefilledSet(weightKg: item.isBodyweight ? 0 : (defaultWeightKg ?? 0), reps: item.repsHigh)
        }
    }

    /// "Last time: 3 × 8 @ 60 kg", or each set when they differ ("60 kg × 8, 60 kg × 8, 62.5 kg × 6").
    public static func lastTimeText(_ previous: [PreviousSet], isBodyweight: Bool, formatWeight: (Double) -> String) -> String? {
        guard let first = previous.first else { return nil }
        if isBodyweight {
            let reps = previous.map(\.reps)
            if Set(reps).count == 1 { return "Last time: \(previous.count) × \(first.reps)" }
            return "Last time: " + reps.map { "\($0)" }.joined(separator: ", ") + " reps"
        }
        if previous.allSatisfy({ $0 == first }) {
            return "Last time: \(previous.count) × \(first.reps) @ \(formatWeight(first.weightKg))"
        }
        return "Last time: " + previous.map { "\(formatWeight($0.weightKg)) × \($0.reps)" }.joined(separator: ", ")
    }
}
