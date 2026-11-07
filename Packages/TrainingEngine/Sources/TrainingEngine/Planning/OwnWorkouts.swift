import Foundation

/// What kind of plan they want (asked in onboarding).
public enum PlanStyle: String, Codable, CaseIterable, Sendable {
    /// Kinetix builds the runs and the gym sessions.
    case kinetix
    /// Kinetix builds the runs; the gym days are "Gym 1, Gym 2…" for their own saved gym workouts.
    case ownGym
    /// Kinetix builds the gym sessions; the runs are "Run 1 · Long, Run 2 · Quality…" for their
    /// own saved run workouts.
    case ownRuns
    /// They build the whole plan themselves in the plan builder.
    case custom

    public var title: String {
        switch self {
        case .kinetix: return "Run and gym, built for me"
        case .ownGym: return "Runs built for me, my own gym workouts"
        case .ownRuns: return "Gym built for me, my own run workouts"
        case .custom: return "I'll build my own plan"
        }
    }
}

/// A saved gym workout linked to a gym day ("Gym 1"), keyed by the day's number.
public struct OwnGymWorkout: Codable, Equatable, Sendable {
    public var name: String
    public var exercises: [GymTemplateItem]
    /// A functional workout (circuit / Hyrox) linked instead of a gym workout.
    public var functional: FunctionalWorkout?

    public init(name: String, exercises: [GymTemplateItem], functional: FunctionalWorkout? = nil) {
        self.name = name
        self.exercises = exercises
        self.functional = functional
    }
}

/// The role a run has in the week, for linking their own run workouts.
public enum RunRole: String, Codable, CaseIterable, Sendable {
    case long, quality1, quality2, easy

    public var title: String {
        switch self {
        case .long: return "Long"
        case .quality1: return "Quality"
        case .quality2: return "Second quality"
        case .easy: return "Easy"
        }
    }
}

public enum OwnWorkouts {
    /// "Gym 1"… for the gym days (the scheduler places them by what the linked workout works).
    public static func gymTemplates(count: Int, linked: [Int: OwnGymWorkout], exercises: [ExerciseDefinition]) -> [StrengthSessionTemplate] {
        (0..<count).map { index in
            let name = "Gym \(index + 1)"
            guard let workout = linked[index + 1], workout.functional == nil else {
                // Not linked yet, or a functional workout: treated as working everything (kept away from hard runs).
                return StrengthSessionTemplate(name: name, focus: .fullBody, slots: [])
            }
            let slots = workout.exercises.map { item in
                ExerciseSlot(pattern: "named", role: .accessory, exerciseName: item.name)
            }
            return StrengthSessionTemplate(name: name, focus: focus(of: workout.exercises, library: exercises), slots: slots)
        }
    }

    /// What a workout mostly works, from its exercises (unknown exercises by name).
    public static func focus(of items: [GymTemplateItem], library: [ExerciseDefinition]) -> StrengthFocus {
        var legs = 0, push = 0, pull = 0
        for item in items {
            let group = library.first { $0.id == item.exerciseId }?.muscleGroup ?? guessGroup(item.name)
            switch group {
            case .legs, .glutes: legs += 1
            case .chest, .shoulders: push += 1
            case .back: pull += 1
            case .arms, .core, .fullBody: break
            }
        }
        let upper = push + pull
        if legs > 0 && upper > 0 { return legs >= upper * 2 ? .legs : .fullBody }
        if legs > 0 { return .legs }
        if push > 0 && pull > 0 { return .upper }
        if push > 0 { return .push }
        if pull > 0 { return .pull }
        return .upper
    }

    private static func guessGroup(_ name: String) -> MuscleGroup {
        let n = name.lowercased()
        if ["squat", "lunge", "leg", "calf", "step-up", "deadlift", "hip thrust", "glute"].contains(where: n.contains) { return .legs }
        if ["row", "pull", "chin", "lat "].contains(where: n.contains) { return .back }
        if ["bench", "press", "chest", "fly", "push", "dip", "lateral", "shoulder"].contains(where: n.contains) { return .chest }
        if ["curl", "tricep", "extension"].contains(where: n.contains) { return .arms }
        return .core
    }

    /// The session for a "Gym n" day: the linked workout's exercises (weights from their working
    /// weights; one set fewer in easier weeks), or nil when it isn't linked yet.
    public static func gymPrescription(slotName: String, linked: [Int: OwnGymWorkout], workingWeights: [String: Double],
                                       lighter: Bool) -> (title: String, prescription: StrengthPrescription?) {
        guard let number = Int(slotName.replacingOccurrences(of: "Gym ", with: "")), let workout = linked[number],
              workout.functional == nil else {
            return (slotName, nil)
        }
        let prescription = StrengthPrescription(exercises: workout.exercises.map { item in
            let key = "\(item.exerciseId).main"
            let weight = item.isBodyweight ? nil : (workingWeights[key] ?? workingWeights["\(item.exerciseId).accessory"] ?? 0)
            return ExercisePrescription(exerciseId: item.exerciseId, name: item.name, role: .main,
                                        sets: lighter ? max(1, item.sets - 1) : item.sets,
                                        repRange: RepRange(item.repsLow, item.repsHigh), weightKg: weight, restSeconds: item.restSeconds)
        })
        return ("\(slotName) · \(workout.name)", prescription)
    }

    /// A "Gym n" day as a session: the linked workout, or a placeholder to choose one.
    public static func gymSession(template: StrengthSessionTemplate, date: Date, slot: SessionSlot, profile: AthleteProfile,
                                  workingWeights: [String: Double], lighter: Bool, effort: Double) -> GeneratedSession {
        if let number = Int(template.name.replacingOccurrences(of: "Gym ", with: "")),
           let functional = profile.ownGymWorkouts?[number]?.functional {
            // A functional workout: opens as one (the app finds it by the day's number).
            return GeneratedSession(date: date, slot: slot, kind: .strength(.fullBody), isKey: false,
                                    title: "\(template.name) · \(functional.name)", summary: "Functional · \(functional.summary)",
                                    plannedDurationMinutes: functional.estimatedMinutes, plannedEffort: max(effort, 7),
                                    estimatedDistanceMeters: nil, runStructure: nil, strength: nil)
        }
        let linked = gymPrescription(slotName: template.name, linked: profile.ownGymWorkouts ?? [:], workingWeights: workingWeights,
                                     lighter: lighter)
        if let prescription = linked.prescription {
            let sets = prescription.exercises.reduce(0) { $0 + $1.sets }
            return GeneratedSession(date: date, slot: slot, kind: .strength(template.focus), isKey: false, title: linked.title,
                                    summary: "\(prescription.exercises.count) exercises · \(sets) sets",
                                    plannedDurationMinutes: StrengthBuilder.estimatedMinutes(prescription), plannedEffort: effort,
                                    estimatedDistanceMeters: nil, runStructure: nil, strength: prescription)
        }
        return GeneratedSession(date: date, slot: slot, kind: .strength(template.focus), isKey: false, title: template.name,
                                summary: "Your gym workout: choose one", plannedDurationMinutes: 60, plannedEffort: effort,
                                estimatedDistanceMeters: nil, runStructure: nil, strength: nil)
    }

    /// Own runs: each run in the week gets its number and role ("Run 2 · Quality"), and a linked
    /// run workout replaces Kinetix's session for that role. The race is left as it is.
    public static func applyRunRoles(_ sessions: [GeneratedSession], linked: [RunRole: CustomRunWorkout],
                                     zones: PaceZones, units: UnitSystem) -> [GeneratedSession] {
        var result = sessions
        let runIndexes = result.indices.filter {
            result[$0].kind.discipline == .run && result[$0].plannedEffort < 9
        }.sorted { result[$0].date < result[$1].date }
        var qualitySeen = 0
        for (number, index) in runIndexes.enumerated() {
            let session = result[index]
            let role: RunRole
            switch session.kind {
            case .run(.long): role = .long
            case .run(.tempo), .run(.intervals):
                qualitySeen += 1
                role = qualitySeen == 1 ? .quality1 : .quality2
            default: role = .easy
            }
            var updated = session
            if let workout = linked[role], let structure = workout.structure {
                let estimate = structure.estimate(zones: zones)
                updated.runStructure = structure
                updated.estimatedDistanceMeters = estimate.distanceMeters
                updated.plannedDurationMinutes = max(5, (estimate.durationSeconds / 60 / 5).rounded() * 5)
                updated.title = "Run \(number + 1) · \(role.title): \(workout.name)"
                updated.summary = workout.summary(units: units)
            } else {
                updated.title = "Run \(number + 1) · \(role.title): \(session.title)"
            }
            result[index] = updated
        }
        return result
    }
}

/// A plan gym day as they like it: exercises added, sets changed, exercises dropped. Applied
/// every week when the day's session is built.
public struct PlanDayChange: Codable, Equatable, Sendable {
    public var added: [GymTemplateItem]
    /// Exercise id → sets.
    public var sets: [String: Int]
    public var removed: [String]

    public init(added: [GymTemplateItem] = [], sets: [String: Int] = [:], removed: [String] = []) {
        self.added = added
        self.sets = sets
        self.removed = removed
    }

    public var isEmpty: Bool { added.isEmpty && sets.isEmpty && removed.isEmpty }
}
