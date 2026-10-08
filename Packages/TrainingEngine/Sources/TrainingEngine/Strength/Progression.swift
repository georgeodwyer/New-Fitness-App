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
        units: UnitSystem = .metric
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

        // Base the next step on what was actually lifted (the lightest working set).
        let base = done.compactMap(\.weightKg).min() ?? state.workingWeightKg
        let rpes = done.compactMap(\.rpe)
        let averageRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
        let allSetsDone = done.count >= prescribedSets
        let hitTop = allSetsDone && done.allSatisfy { $0.reps >= repRange.upper }
        let missed = !allSetsDone || done.contains { $0.reps < repRange.lower }
        let effortOK = averageRPE.map { $0 <= rules.maxRPEForIncrease } ?? true
        let weightText = { (kg: Double) in Units.formatWeight(kg: kg, units: units) + " " + Units.weightUnitLabel(units) }
        let setsText = "\(done.count)×\(repRange.upper)"

        if hitTop && effortOK {
            let step = rules.increment(loading: loading, region: region)
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

        // In range but not yet at the top: keep adding reps.
        return ProgressionDecision(
            newState: ProgressionState(workingWeightKg: base, stallCount: 0),
            change: .hold,
            reason: "\(exerciseName): staying at \(weightText(base)). Aim for \(repRange.upper) reps on every set to earn an increase."
        )
    }

    static func formatRPE(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
