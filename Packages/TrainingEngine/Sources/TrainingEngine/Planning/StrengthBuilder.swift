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

    /// Working weight from a lift the runner entered (e.g. 90 kg × 3) for a rep range starting
    /// at `reps`, with about two reps in reserve. An accessory use of a main lift is 80% of it.
    public static func weight(from estimate: LiftEstimate, reps: Int, accessory: Bool, loading: ExerciseLoading) -> Double {
        let oneRM = estimatedOneRepMax(weightKg: estimate.weightKg, reps: max(estimate.reps, 1))
        let target = workingWeight(oneRepMax: oneRM, reps: reps)
        return roundDown(accessory ? target * 0.8 : target, loading: loading)
    }

    /// Working weight from their lift numbers for a main lift, or a variation linked to one
    /// (nil when the exercise isn't linked or they haven't given that lift).
    public static func weight(for exercise: ExerciseDefinition, estimates: [LiftEstimate], reps: Int, accessory: Bool) -> Double? {
        func estimate(_ lift: MainLift) -> LiftEstimate? { estimates.first { $0.lift == lift && $0.weightKg > 0 } }
        if let lift = exercise.mainLift, let found = estimate(lift) {
            return weight(from: found, reps: reps, accessory: accessory, loading: exercise.loading)
        }
        guard let link = exercise.liftLink, let found = estimate(link.lift) else { return nil }
        let oneRM = estimatedOneRepMax(weightKg: found.weightKg, reps: max(found.reps, 1))
        return roundDown(workingWeight(oneRepMax: oneRM, reps: reps) * link.ratio, loading: exercise.loading)
    }

    /// A heavy week's weight: about 5% over the working weight, to the nearest loadable step
    /// (at least one step heavier).
    public static func heavyWeight(working: Double, loading: ExerciseLoading) -> Double {
        let step = increment(for: loading)
        guard step > 0, working > 0 else { return working }
        return max(working + step, (working * 1.05 / step).rounded() * step)
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
        /// A heavy week: main lifts about 5% heavier for the bottom of the rep range.
        var heavy = false
    }

    static func prescription(for session: StrengthSessionTemplate, context: Context) -> StrengthPrescription {
        let templates = context.templates
        let goalPrescription = templates.prescription(for: context.profile.goal)
            ?? GoalPrescription(main: SetScheme(sets: 3, repsLow: 6, repsHigh: 8, restSeconds: 120),
                                accessory: SetScheme(sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 75))
        var exercises: [ExercisePrescription] = []
        var used = Set<String>()
        // What they've changed on this day and kept.
        let change = context.profile.planDayChanges?[session.name]
        func adjusted(_ sets: Int) -> Int {
            if context.week.phase == .taper {
                return max(1, Int((Double(sets) * templates.strength.taperSetMultiplier).rounded()))
            } else if context.week.isRecoveryWeek {
                return max(2, sets - 1)
            }
            return sets
        }

        for slot in session.slots {
            guard var exercise = templates.exercise(for: slot, equipment: context.profile.equipment) else { continue }
            // The runner's own swap for this day, where they kept one.
            if let swapId = context.profile.exerciseSwaps?[AthleteProfile.swapKey(day: session.name, exerciseId: exercise.id)],
               let swapped = templates.exercise(id: swapId) {
                exercise = swapped
            }
            guard !used.contains(exercise.id) else { continue }
            used.insert(exercise.id)
            if change?.removed.contains(exercise.id) == true { continue }

            var scheme = slot.role == .main ? goalPrescription.main : goalPrescription.accessory
            // The coach's sets/reps/rest for this exercise, where written.
            if let sets = slot.sets { scheme.sets = sets }
            if let low = slot.repsLow { scheme.repsLow = low }
            if let high = slot.repsHigh { scheme.repsHigh = max(high, scheme.repsLow) }
            if let rest = slot.restSeconds { scheme.restSeconds = rest }
            if let kept = change?.sets[exercise.id] { scheme.sets = kept }
            let sets = adjusted(scheme.sets)

            var reps: RepRange
            var weight: Double?
            var isHeavy: Bool?
            if exercise.loading == .bodyweight {
                // The coach's reps (or metres, for stations) where written, else the bodyweight default.
                reps = slot.repsLow != nil || slot.repsHigh != nil
                    ? RepRange(scheme.repsLow, scheme.repsHigh)
                    : RepRange(templates.strength.bodyweightReps.repsLow, templates.strength.bodyweightReps.repsHigh)
                weight = nil
            } else {
                reps = RepRange(scheme.repsLow, scheme.repsHigh)
                let key = "\(exercise.id).\(slot.role.rawValue)"
                weight = context.workingWeights[key]
                    ?? startingWeight(for: exercise, role: slot.role, reps: reps, profile: context.profile)
                if context.heavy, slot.role == .main, let working = weight, working > 0 {
                    weight = StrengthMath.heavyWeight(working: working, loading: exercise.loading)
                    reps = RepRange(reps.lower, reps.lower)
                    isHeavy = true
                }
            }

            exercises.append(ExercisePrescription(
                exerciseId: exercise.id,
                name: exercise.name,
                role: slot.role,
                sets: sets,
                repRange: reps,
                weightKg: weight,
                restSeconds: scheme.restSeconds,
                isHeavy: isHeavy
            ))
        }
        // Exercises they added to this day and kept.
        for item in change?.added ?? [] where used.insert(item.exerciseId).inserted {
            let definition = templates.exercise(id: item.exerciseId)
            let reps = RepRange(item.repsLow, item.repsHigh)
            var weight: Double?
            if !item.isBodyweight {
                weight = context.workingWeights["\(item.exerciseId).accessory"]
                    ?? definition.flatMap { startingWeight(for: $0, role: .accessory, reps: reps, profile: context.profile) } ?? 0
            }
            exercises.append(ExercisePrescription(exerciseId: item.exerciseId, name: item.name, role: .accessory,
                                                  sets: adjusted(change?.sets[item.exerciseId] ?? item.sets), repRange: reps,
                                                  weightKg: weight, restSeconds: item.restSeconds))
        }
        return StrengthPrescription(exercises: exercises)
    }

    /// Starting weight: from their lift numbers for main lifts and linked variations, else a
    /// default for their level. Machines with no default start at 0 ("pick a weight").
    static func startingWeight(for exercise: ExerciseDefinition, role: SlotRole, reps: RepRange, profile: AthleteProfile) -> Double? {
        if let weight = StrengthMath.weight(for: exercise, estimates: profile.liftEstimates, reps: reps.lower, accessory: role == .accessory) {
            return weight
        }
        // Hyrox stations start at the race weight for their division.
        if let division = profile.hyroxDivision, let race = exercise.defaultWeightKg?["hyrox-" + division.rawValue] {
            return race
        }
        guard let base = exercise.defaultWeight(for: profile.liftingExperience) else {
            return exercise.loading == .machine ? 0 : nil
        }
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
