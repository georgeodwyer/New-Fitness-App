import Foundation

/// At most a few notifications a day: the most useful ones win. Workout results and personal
/// bests (`exempt`) always come through and don't count.
public enum NotificationBudget {
    /// Notifications a day, not counting exempt ones.
    public static let dailyCap = 3

    public struct Candidate: Equatable, Sendable {
        public var id: String
        /// The day it's for (start of day).
        public var day: Date
        /// Lower is more important.
        public var priority: Int
        public var exempt: Bool

        public init(id: String, day: Date, priority: Int, exempt: Bool = false) {
            self.id = id
            self.day = day
            self.priority = priority
            self.exempt = exempt
        }
    }

    /// The ones to send: every exempt one, and on each day the most important others up to the
    /// cap, less any already used that day (ties keep their order).
    public static func pick(_ candidates: [Candidate], cap: Int = dailyCap, used: [Date: Int] = [:]) -> Set<String> {
        var chosen = Set(candidates.filter(\.exempt).map(\.id))
        let byDay = Dictionary(grouping: candidates.enumerated().filter { !$0.element.exempt }, by: { $0.element.day })
        for (day, items) in byDay {
            let room = max(0, cap - (used[day] ?? 0))
            let ranked = items.sorted { $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority < $1.element.priority }
            chosen.formUnion(ranked.prefix(room).map(\.element.id))
        }
        return chosen
    }

    /// How many non-exempt ones are picked on each day.
    public static func countByDay(_ candidates: [Candidate], picked: Set<String>) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for candidate in candidates where !candidate.exempt && picked.contains(candidate.id) {
            counts[candidate.day, default: 0] += 1
        }
        return counts
    }
}
