import Foundation

/// Tunable progression settings (loaded from strength_programmes.json → "progression").
public struct ProgressionRules: Codable, Equatable, Sendable {
    /// Load added after a successful session, by equipment and body region (kg).
    public var increments: [String: [String: Double]]
    /// Highest average set RPE that still counts as "acceptable effort" for an increase.
    public var maxRPEForIncrease: Double
    /// Consecutive sessions with missed reps before a deload.
    public var stallsBeforeDeload: Int
    /// Fraction removed on a deload (0.1 = 10% lighter).
    public var deloadFraction: Double

    public static let standard = ProgressionRules(
        increments: [
            "barbell": ["upper": 2.5, "lower": 5, "core": 2.5],
            "machine": ["upper": 2.5, "lower": 5, "core": 2.5],
            // Most dumbbell racks go up in 2 kg steps, so upper and lower body match here.
            "dumbbell": ["upper": 2, "lower": 2, "core": 2]
        ],
        maxRPEForIncrease: 9,
        stallsBeforeDeload: 3,
        deloadFraction: 0.1
    )

    public func increment(loading: ExerciseLoading, region: BodyRegion) -> Double {
        increments[loading.rawValue]?[region.rawValue] ?? StrengthMath.increment(for: loading)
    }

    /// Below this, lower-body barbell and machine lifts go up 2.5 kg rather than 5 kg (5 kg on a
    /// 70 kg squat is a 7% jump).
    public static let smallerLowerStepBelowKg = 100.0
    /// A step bigger than this share of the weight is a big jump (2 kg on an 8 kg dumbbell is 25%):
    /// earn it with two reps past the top of the range first.
    public static let bigStepShare = 0.12
    public static let extraRepsForBigStep = 2

    /// The step for this weight: about 2.5–5% for most lifts, as the gym can load it.
    public func increment(loading: ExerciseLoading, region: BodyRegion, weightKg: Double) -> Double {
        let step = increment(loading: loading, region: region)
        if region == .lower, loading == .barbell || loading == .machine, weightKg > 0, weightKg < Self.smallerLowerStepBelowKg {
            return min(step, 2.5)
        }
        return step
    }

    /// Reps every set needs before the weight goes up: the top of the range, or two more when
    /// the next step is a big jump for this weight.
    public func repsForIncrease(repRange: RepRange, loading: ExerciseLoading, region: BodyRegion, weightKg: Double) -> Int {
        guard loading != .bodyweight, weightKg > 0 else { return repRange.upper }
        let step = increment(loading: loading, region: region, weightKg: weightKg)
        return step / weightKg > Self.bigStepShare ? repRange.upper + Self.extraRepsForBigStep : repRange.upper
    }
}

/// One logged set.
public struct SetResult: Codable, Equatable, Sendable {
    public var weightKg: Double?
    public var reps: Int
    public var rpe: Double?
    public var completed: Bool

    public init(weightKg: Double?, reps: Int, rpe: Double? = nil, completed: Bool = true) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.completed = completed
    }
}

/// Where an exercise stands in its progression.
public struct ProgressionState: Codable, Equatable, Sendable {
    public var workingWeightKg: Double
    /// Consecutive sessions in which reps were missed.
    public var stallCount: Int

    public init(workingWeightKg: Double, stallCount: Int = 0) {
        self.workingWeightKg = workingWeightKg
        self.stallCount = stallCount
    }
}

public struct ProgressionDecision: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case increase(byKg: Double)
        case hold
        case deload(byKg: Double)
        /// Nothing logged, or a bodyweight exercise: weight is unaffected.
        case none
    }

    public var newState: ProgressionState
    public var change: Change
    /// One plain-English sentence explaining what changed and why.
    public var reason: String
}

/// Double progression: work within a rep range at a fixed weight; once every set reaches
/// the top of the range at an acceptable effort, add weight (less for upper body). Missed
/// reps hold the weight; repeated misses trigger a deload.
public enum Progression {
    public static func evaluate(
        exerciseName: String,
        loading: ExerciseLoading,
        region: BodyRegion,
        repRange: RepRange,
        prescribedSets: Int,
        state: ProgressionState,
        sets: [SetResult],
        rules: ProgressionRules = .standard,
        units: UnitSystem = .metric,
        countsMisses: Bool = true
    ) -> ProgressionDecision {
        let done = sets.filter(\.completed)
        guard !done.isEmpty else {
            return ProgressionDecision(newState: state, change: .none, reason: "\(exerciseName): no sets logged, so nothing changes.")
        }

        if loading == .bodyweight {
            let allTop = done.count >= prescribedSets && done.allSatisfy { $0.reps >= repRange.upper }
            let reason = allTop
                ? "\(exerciseName): you hit \(repRange.upper) reps on every set. Slow the tempo or add a pause to make it harder."
                : "\(exerciseName): keep working towards \(repRange.upper) reps on every set."
            return ProgressionDecision(newState: state, change: .none, reason: reason)
        }

        // The weight to judge against: the working weight, or what they chose instead when every
        // set was lighter (or heavier). One lighter set doesn't pull the weight down.
        let weights = done.compactMap(\.weightKg)
        let working = state.workingWeightKg
        let lightest = weights.min() ?? working
        let allLighter = working > 0 && !weights.isEmpty && weights.allSatisfy { $0 < working - 0.01 }
        let base = working <= 0 || allLighter ? lightest : max(working, lightest)
        // Only sets at that weight count: every prescribed set must reach the top of the range there.
        let atWeight = done.filter { ($0.weightKg ?? base) >= base - 0.01 }
        let rpes = atWeight.compactMap(\.rpe)
        let averageRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
        let allSetsDone = atWeight.count >= prescribedSets
        let needed = rules.repsForIncrease(repRange: repRange, loading: loading, region: region, weightKg: base)
        let hitTop = allSetsDone && atWeight.allSatisfy { $0.reps >= needed }
        // Only failed reps count against you. Sets not done (a session cut short) just hold the weight.
        let missed = atWeight.contains { $0.reps < repRange.lower }
        let effortOK = averageRPE.map { $0 <= rules.maxRPEForIncrease } ?? true
        let weightText = { (kg: Double) in Units.formatWeight(kg: kg, units: units) + " " + Units.weightUnitLabel(units) }
        let setsText = "\(atWeight.count)×\(needed)"

        if hitTop && effortOK {
            let step = rules.increment(loading: loading, region: region, weightKg: base)
            let next = ((base + step) * 2).rounded() / 2 // nearest 0.5 kg
            let effortText = averageRPE.map { " at RPE \(formatRPE($0))" } ?? ""
            return ProgressionDecision(
                newState: ProgressionState(workingWeightKg: next, stallCount: 0),
                change: .increase(byKg: next - base),
                reason: "\(exerciseName): +\(weightText(next - base)) to \(weightText(next)). You hit \(setsText)\(effortText)."
            )
        }

        if hitTop {
            return ProgressionDecision(
                newState: ProgressionState(workingWeightKg: base, stallCount: 0),
                change: .hold,
                reason: "\(exerciseName): staying at \(weightText(base)). You hit every rep, but it was very hard, so let's own this weight first."
            )
        }

        if missed && !countsMisses {
            return ProgressionDecision(
                newState: ProgressionState(workingWeightKg: base, stallCount: state.stallCount),
                change: .hold,
                reason: "\(exerciseName): staying at \(weightText(base)). Some reps fell short, but your recovery was low today, so it doesn't count towards a reset."
            )
        }

        // A light lift where each step is a big jump (2 kg on 10 kg is 20%): reps fall short for a
        // while after going up. Hold while they build back; never count it towards a reset.
        if missed && needed > repRange.upper {
            return ProgressionDecision(
                newState: ProgressionState(workingWeightKg: base, stallCount: 0),
                change: .hold,
                reason: "\(exerciseName): staying at \(weightText(base)). Steps are big at this weight, so reps take a while to build back up; it won't count towards a reset."
            )
        }

        if missed {
            let stalls = state.stallCount + 1
            if stalls >= rules.stallsBeforeDeload {
                let next = StrengthMath.roundDown(base * (1 - rules.deloadFraction), loading: loading)
                return ProgressionDecision(
                    newState: ProgressionState(workingWeightKg: next, stallCount: 0),
                    change: .deload(byKg: base - next),
                    reason: "\(exerciseName): down to \(weightText(next)). Reps were missed \(stalls) sessions running, so a lighter reset will help you build back stronger."
                )
            }
            return ProgressionDecision(
                newState: ProgressionState(workingWeightKg: base, stallCount: stalls),
                change: .hold,
                reason: "\(exerciseName): staying at \(weightText(base)). Some reps fell short of \(repRange.lower), so have another go."
            )
        }

        if !allSetsDone {
            return ProgressionDecision(
                newState: ProgressionState(workingWeightKg: base, stallCount: state.stallCount),
                change: .hold,
                reason: "\(exerciseName): staying at \(weightText(base)). You did \(atWeight.count) of \(prescribedSets) sets at that weight, so do them all to earn an increase."
            )
        }

        // In range but not yet at the top: keep adding reps.
        return ProgressionDecision(
            newState: ProgressionState(workingWeightKg: base, stallCount: 0),
            change: .hold,
            reason: needed > repRange.upper
                ? "\(exerciseName): staying at \(weightText(base)). The next step is a big jump at this weight, so aim for \(needed) reps on every set first."
                : "\(exerciseName): staying at \(weightText(base)). Aim for \(repRange.upper) reps on every set to earn an increase."
        )
    }

    static func formatRPE(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
