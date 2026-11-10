import Foundation

/// Whether next week's running grows as planned, from how the last two weeks went.
///
/// - Under 80% of the running planned (counted from the sessions planned, so a week the app
///   planned short never counts against you) two weeks in a row: next week holds where it is.
/// - "Too much" at the weekly check-in two weeks in a row: next week holds.
/// - "Too easy" two weeks in a row: next week may grow up to 15% (instead of 10%).
/// Holding pauses growth for one week; the plan grows again from there as usual.
public enum PlanAdaptation {
    public struct WeekResult: Equatable, Sendable {
        /// Running in the week's planned sessions.
        public var plannedRunMeters: Double
        /// Of that, the sessions done (shortened for recovery or swapped by the app count as done).
        public var doneRunMeters: Double
        /// Their answer at the weekly check-in, if they gave one.
        public var feel: WeekFeel?

        public init(plannedRunMeters: Double, doneRunMeters: Double, feel: WeekFeel?) {
            self.plannedRunMeters = plannedRunMeters
            self.doneRunMeters = doneRunMeters
            self.feel = feel
        }

        public var completion: Double? { plannedRunMeters > 0 ? doneRunMeters / plannedRunMeters : nil }
    }

    public struct Decision: Equatable, Sendable {
        /// Next week's base doesn't grow.
        public var hold: Bool
        /// The most next week may grow over the biggest of the three before it (nil: the usual 10%).
        public var limit: Double?
        /// Why, in a sentence (nil when the plan carries on as planned).
        public var reason: String?

        public init(hold: Bool, limit: Double?, reason: String?) {
            self.hold = hold
            self.limit = limit
            self.reason = reason
        }

        public static let asPlanned = Decision(hold: false, limit: nil, reason: nil)
        public var changesPlan: Bool { hold || limit != nil }
    }

    public static let underPlanned = 0.8
    public static let tooEasyLimit = 0.15

    /// - Parameter lastTwo: the two weeks before this one, oldest first.
    public static func decide(_ lastTwo: [WeekResult]) -> Decision {
        guard lastTwo.count == 2 else { return .asPlanned }
        let completions = lastTwo.compactMap(\.completion)
        if completions.count == 2, completions.allSatisfy({ $0 < underPlanned }) {
            let first = Int((completions[0] * 100).rounded()), second = Int((completions[1] * 100).rounded())
            return Decision(hold: true, limit: nil,
                            reason: "You ran \(first)% and \(second)% of your planned running the last two weeks, so next week holds instead of growing. It grows again from there.")
        }
        if lastTwo.allSatisfy({ $0.feel == .tooMuch }) {
            return Decision(hold: true, limit: nil,
                            reason: "You said the last two weeks were too much, so next week's running holds instead of growing.")
        }
        if lastTwo.allSatisfy({ $0.feel == .tooEasy }) {
            return Decision(hold: false, limit: tooEasyLimit,
                            reason: "You said the last two weeks were too easy, so next week can grow up to 15% instead of 10%.")
        }
        return .asPlanned
    }
}
