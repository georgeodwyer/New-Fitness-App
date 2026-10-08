import Foundation

public enum StrengthMath {
    /// Estimated one-rep max (Epley formula).
    public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double {
        reps <= 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    /// Weight you could lift for `reps` with about `reserve` reps left in the tank.
    public static func workingWeight(oneRepMax: Double, reps: Int, reserve: Int = 2) -> Double {
        oneRepMax / (1 + Double(reps + reserve) / 30)
    }

    /// Smallest sensible load jump for the equipment.
    public static func increment(for loading: ExerciseLoading) -> Double {
        switch loading {
        case .barbell, .machine: return 2.5
        case .dumbbell: return 2
        case .bodyweight: return 0
        }
    }

    /// Rounds down to a loadable weight.
    public static func roundDown(_ weight: Double, loading: ExerciseLoading) -> Double {
        let step = increment(for: loading)
        guard step > 0 else { return weight }
        return max(step, (weight / step).rounded(.down) * step)
    }
}

enum StrengthBuilder {
    struct Context {
        var profile: AthleteProfile
        var templates: TemplateLibrary
        var week: WeekTarget
        /// Current working weights by progression key (from the progression engine).
        var workingWeights: [String: Double]
    }

    static func prescription(for session: StrengthSessionTemplate, context: Context) -> StrengthPrescription {
        let templates = context.templates
        let goalPrescription = templates.prescription(for: context.profile.goal)
            ?? GoalPrescription(main: SetScheme(sets: 3, repsLow: 6, repsHigh: 8, restSeconds: 120),
                                accessory: SetScheme(sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 75))
        var exercises: [ExercisePrescription] = []
        var used = Set<String>()

        for slot in session.slots {
            guard let exercise = templates.exercise(pattern: slot.pattern, equipment: context.profile.equipment),
                  !used.contains(exercise.id) else { continue }
            used.insert(exercise.id)

            let scheme = slot.role == .main ? goalPrescription.main : goalPrescription.accessory
            var sets = scheme.sets
            if context.week.phase == .taper {
                sets = max(1, Int((Double(sets) * templates.strength.taperSetMultiplier).rounded()))
            } else if context.week.isRecoveryWeek {
                sets = max(2, sets - 1)
            }

            let reps: RepRange
            let weight: Double?
            if exercise.loading == .bodyweight {
                reps = RepRange(templates.strength.bodyweightReps.repsLow, templates.strength.bodyweightReps.repsHigh)
                weight = nil
            } else {
                reps = RepRange(scheme.repsLow, scheme.repsHigh)
                let key = "\(exercise.id).\(slot.role.rawValue)"
                weight = context.workingWeights[key]
                    ?? startingWeight(for: exercise, role: slot.role, reps: reps, profile: context.profile)
            }

            exercises.append(ExercisePrescription(
                exerciseId: exercise.id,
                name: exercise.name,
                role: slot.role,
                sets: sets,
                repRange: reps,
                weightKg: weight,
                restSeconds: scheme.restSeconds
            ))
        }
        return StrengthPrescription(exercises: exercises)
    }

    /// Starting weight: from the user's estimate for main lifts, else a default for their level.
    static func startingWeight(for exercise: ExerciseDefinition, role: SlotRole, reps: RepRange, profile: AthleteProfile) -> Double? {
        if let lift = exercise.mainLift,
           let estimate = profile.liftEstimates.first(where: { $0.lift == lift }),
           estimate.weightKg > 0 {
            let oneRM = StrengthMath.estimatedOneRepMax(weightKg: estimate.weightKg, reps: max(estimate.reps, 1))
            let target = StrengthMath.workingWeight(oneRepMax: oneRM, reps: reps.lower)
            // Accessory use of a main lift is lighter.
            let scaled = role == .accessory ? target * 0.8 : target
            return StrengthMath.roundDown(scaled, loading: exercise.loading)
        }
        guard let base = exercise.defaultWeight(for: profile.liftingExperience) else { return nil }
        let scaled = role == .accessory && exercise.mainLift != nil ? base * 0.8 : base
        return StrengthMath.roundDown(scaled, loading: exercise.loading)
    }

    /// Rough session length: warm-up plus each set's work and rest.
    static func estimatedMinutes(_ prescription: StrengthPrescription) -> Double {
        let seconds = prescription.exercises.reduce(600.0) { total, exercise in
            let work = Double(exercise.repRange.upper) * 4
            return total + Double(exercise.sets) * (work + Double(exercise.restSeconds))
        }
        return (seconds / 60 / 5).rounded() * 5
    }
}
