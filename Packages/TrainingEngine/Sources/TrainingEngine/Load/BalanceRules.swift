import Foundation

/// Tunable thresholds for scheduling, load, recovery and rebalancing, loaded from
/// `Resources/balance_rules.json` so they can be changed without touching code.
/// (docs/RULES.md explains each value.)
public struct BalanceRules: Codable, Equatable, Sendable {
    public struct Scheduling: Codable, Equatable, Sendable {
        /// No heavy legs within ~24 h before a quality or long run.
        public var noLowerBodyLiftDayBeforeHardRun: Bool
        public var noLowerBodyLiftOnLongRunDay: Bool
        /// "Hard days hard": prefer putting leg sessions on quality-run days (when doubles allow).
        public var pairLowerBodyLiftsWithHardRuns: Bool
    }

    public struct Load: Codable, Equatable, Sendable {
        public var optimalRatioLow: Double
        public var optimalRatioHigh: Double
        public var minimumHistoryDays: Int
    }

    public struct Recovery: Codable, Equatable, Sendable {
        public var poorReadinessBelow: Double
        public var verySoreAtOrAbove: Int
        public var restingHeartRateElevatedBpm: Double
        public var restingHeartRateMinimumReadings: Int
        /// A raised resting HR (or low HRV) only counts as poor recovery when readiness is also below this.
        public var bodySignalCountsWhenReadinessBelow: Double
    }

    public struct Rebalancing: Codable, Equatable, Sendable {
        public var easeHardSessionWithinDays: Int
        public var highLoadEasyRunFactor: Double
        public var minimumEasyRunMinutes: Double
        public var reducedLiftSetsFactor: Double
        public var easedLongRunFactor: Double
        public var easedRunMaxMinutes: Double
    }

    public var scheduling: Scheduling
    public var load: Load
    public var recovery: Recovery
    public var rebalancing: Rebalancing

    /// The values Kinetix was designed with (also used if the file can't be read).
    public static let defaults = BalanceRules(
        scheduling: Scheduling(noLowerBodyLiftDayBeforeHardRun: true, noLowerBodyLiftOnLongRunDay: true, pairLowerBodyLiftsWithHardRuns: true),
        load: Load(optimalRatioLow: 0.8, optimalRatioHigh: 1.3, minimumHistoryDays: 14),
        recovery: Recovery(poorReadinessBelow: 0.42, verySoreAtOrAbove: 5, restingHeartRateElevatedBpm: 7,
                           restingHeartRateMinimumReadings: 7, bodySignalCountsWhenReadinessBelow: 0.6),
        rebalancing: Rebalancing(easeHardSessionWithinDays: 3, highLoadEasyRunFactor: 0.8, minimumEasyRunMinutes: 20,
                                 reducedLiftSetsFactor: 0.6, easedLongRunFactor: 0.6, easedRunMaxMinutes: 45)
    )

    /// The rules in use: the bundled file, or the defaults if it's missing or invalid.
    public static let current: BalanceRules = (try? bundled()) ?? defaults

    public static func bundled() throws -> BalanceRules {
        guard let url = Bundle.module.url(forResource: "balance_rules", withExtension: "json") else {
            throw TemplateError.missingResource("balance_rules")
        }
        let rules = try JSONDecoder().decode(BalanceRules.self, from: Data(contentsOf: url))
        try rules.validate()
        return rules
    }

    /// Rejects values that would break the app (rather than just train differently).
    public func validate() throws {
        func check(_ ok: Bool, _ message: String) throws { if !ok { throw TemplateError.invalid(message) } }
        try check(load.optimalRatioLow > 0 && load.optimalRatioLow < load.optimalRatioHigh, "load: optimalRatioLow must be above 0 and below optimalRatioHigh")
        try check((7...28).contains(load.minimumHistoryDays), "load: minimumHistoryDays must be 7–28")
        try check((0...1).contains(recovery.poorReadinessBelow), "recovery: poorReadinessBelow must be 0–1")
        try check((1...5).contains(recovery.verySoreAtOrAbove), "recovery: verySoreAtOrAbove must be 1–5")
        try check(recovery.restingHeartRateElevatedBpm > 0, "recovery: restingHeartRateElevatedBpm must be positive")
        try check(recovery.restingHeartRateMinimumReadings >= 3, "recovery: restingHeartRateMinimumReadings must be at least 3")
        try check((0...1).contains(recovery.bodySignalCountsWhenReadinessBelow), "recovery: bodySignalCountsWhenReadinessBelow must be 0–1")
        try check((1...7).contains(rebalancing.easeHardSessionWithinDays), "rebalancing: easeHardSessionWithinDays must be 1–7")
        for (name, value) in [("highLoadEasyRunFactor", rebalancing.highLoadEasyRunFactor), ("reducedLiftSetsFactor", rebalancing.reducedLiftSetsFactor),
                              ("easedLongRunFactor", rebalancing.easedLongRunFactor)] {
            try check(value > 0 && value <= 1, "rebalancing: \(name) must be above 0 and at most 1")
        }
        try check(rebalancing.minimumEasyRunMinutes >= 10, "rebalancing: minimumEasyRunMinutes must be at least 10")
        try check(rebalancing.easedRunMaxMinutes >= rebalancing.minimumEasyRunMinutes, "rebalancing: easedRunMaxMinutes must be at least minimumEasyRunMinutes")
    }
}

extension BalanceRules.Load {
    public var optimalRange: ClosedRange<Double> { optimalRatioLow...optimalRatioHigh }
}
