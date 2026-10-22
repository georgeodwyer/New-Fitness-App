import Foundation

public enum TemplateError: Error, Equatable {
    case missingResource(String)
    case invalid(String)
}

/// All data-driven training templates. Loaded from the JSON files bundled in the
/// engine (`Resources/`), so programmes can be tweaked without code changes.
public struct TemplateLibrary: Sendable {
    public var runWorkouts: [RunWorkoutTemplate]
    public var exercises: [ExerciseDefinition]
    public var strength: StrengthProgrammeFile
    public var rules: PlanRules
    /// Programmes written by the coach (goals without one use the rule-based planner).
    public var programmes: ProgrammeFile

    public init(runWorkouts: [RunWorkoutTemplate], exercises: [ExerciseDefinition], strength: StrengthProgrammeFile, rules: PlanRules,
                programmes: ProgrammeFile = .empty) {
        self.runWorkouts = runWorkouts
        self.exercises = exercises
        self.strength = strength
        self.rules = rules
        self.programmes = programmes
    }

    /// Loads the templates shipped with the app.
    public static func bundled() throws -> TemplateLibrary {
        try TemplateLibrary(
            runWorkouts: load(RunWorkoutFile.self, "run_workouts").workouts,
            exercises: load(ExerciseFile.self, "exercises").exercises,
            strength: load(StrengthProgrammeFile.self, "strength_programmes"),
            rules: load(PlanRules.self, "plan_rules"),
            programmes: bundledProgrammes()
        )
    }

    /// Loads templates from JSON data (e.g. a remote override in future).
    public static func decode(runWorkouts: Data, exercises: Data, strength: Data, rules: Data) throws -> TemplateLibrary {
        let decoder = JSONDecoder()
        return try TemplateLibrary(
            runWorkouts: decoder.decode(RunWorkoutFile.self, from: runWorkouts).workouts,
            exercises: decoder.decode(ExerciseFile.self, from: exercises).exercises,
            strength: decoder.decode(StrengthProgrammeFile.self, from: strength),
            rules: decoder.decode(PlanRules.self, from: rules)
        )
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw TemplateError.missingResource(name)
        }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    // MARK: Lookups

    /// Progression list of workouts for a type and level (falls back to the nearest level).
    public func workouts(type: RunSessionType, level: ExperienceLevel) -> [RunWorkoutTemplate] {
        let exact = runWorkouts.filter { $0.type == type && $0.level == level }
        if !exact.isEmpty { return exact }
        return runWorkouts.filter { $0.type == type }
    }

    /// The best exercise for a movement pattern given the user's equipment.
    public func exercise(pattern: String, equipment: Equipment) -> ExerciseDefinition? {
        exercises.first { $0.pattern == pattern && $0.libraryOnly != true && equipment.allows($0.requires) }
    }

    public func exercise(id: String) -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    /// Session templates for a number of lifting days per week (capped at the largest split).
    public func split(liftingDays: Int) -> [StrengthSessionTemplate] {
        guard liftingDays > 0 else { return [] }
        let available = strength.splits.keys.compactMap(Int.init).sorted()
        let key = available.last(where: { $0 <= liftingDays }) ?? available.first ?? 1
        return (strength.splits[String(key)] ?? []).compactMap { strength.sessions[$0] }
    }

    /// Gym sessions for the week: the user's chosen split (its days in order, repeated if they
    /// lift more often than it has days), or the built-in split for that many sessions.
    public func liftTemplates(for profile: AthleteProfile, count: Int) -> [StrengthSessionTemplate] {
        guard count > 0 else { return [] }
        if let code = profile.splitCode, let days = programmes.strength?.split(code)?.days, !days.isEmpty {
            return (0..<count).map { days[$0 % days.count] }
        }
        return Array(split(liftingDays: count).prefix(count))
    }

    /// The exercise for a slot: a pattern chosen for the user's equipment, or the coach's
    /// named exercise (or the closest swap their equipment allows).
    public func exercise(for slot: ExerciseSlot, equipment: Equipment) -> ExerciseDefinition? {
        guard let name = slot.exerciseName else { return exercise(pattern: slot.pattern, equipment: equipment) }
        guard let named = exercises.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        if equipment.allows(named.requires) { return named }
        if let swap = exercise(pattern: named.pattern, equipment: equipment) { return swap }
        let muscle = named.muscleGroup
        return exercises.first { $0.id != named.id && $0.muscleGroup == muscle && equipment.allows($0.requires) }
    }

    public func prescription(for goal: TrainingGoal) -> GoalPrescription? {
        if let fromWorkbook = programmes.strength?.byGoal[goal.rawValue] { return fromWorkbook }
        let key: String
        switch goal {
        case .buildStrength: key = "buildStrength"
        case .buildMuscle: key = "buildMuscle"
        case .balancedHybrid, .hyrox: key = "balancedHybrid"
        case .first5k, .faster5k, .faster10k, .halfMarathon, .marathon: key = "running"
        }
        return strength.prescriptions[key]
    }

    /// Checks internal consistency: every slot resolves to an exercise for every
    /// equipment level, splits reference real sessions, and every goal has rules.
    public func validate() throws {
        for (name, session) in strength.sessions {
            for slot in session.slots {
                for equipment in Equipment.allCases where exercise(pattern: slot.pattern, equipment: equipment) == nil {
                    throw TemplateError.invalid("No \(slot.pattern) exercise for \(equipment.rawValue) (session \(name))")
                }
            }
        }
        for (key, names) in strength.splits {
            for name in names where strength.sessions[name] == nil {
                throw TemplateError.invalid("Split \(key) references unknown session \(name)")
            }
        }
        for goal in TrainingGoal.allCases {
            if rules.goals[goal.rawValue] == nil { throw TemplateError.invalid("No rules for goal \(goal.rawValue)") }
            if prescription(for: goal) == nil { throw TemplateError.invalid("No prescription for goal \(goal.rawValue)") }
            for level in ExperienceLevel.allCases where rules.peakVolumeMeters[goal.rawValue]?[level.rawValue] == nil {
                throw TemplateError.invalid("No peak volume for \(goal.rawValue)/\(level.rawValue)")
            }
        }
        for type in [RunSessionType.tempo, .intervals] {
            for level in ExperienceLevel.allCases where workouts(type: type, level: level).isEmpty {
                throw TemplateError.invalid("No \(type.rawValue) workouts for \(level.rawValue)")
            }
        }
    }
}
