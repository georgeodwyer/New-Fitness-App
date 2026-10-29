import Foundation

/// A finished (or nearly finished) week in a few numbers and one sentence, for the Sunday
/// review: sessions done, distance against plan, gym sessions, load against usual.
public struct WeekReview: Equatable, Sendable {
    public struct Session: Equatable, Sendable {
        public var discipline: Discipline
        public var status: SessionStatus
        public var plannedMeters: Double

        public init(discipline: Discipline, status: SessionStatus, plannedMeters: Double = 0) {
            self.discipline = discipline
            self.status = status
            self.plannedMeters = plannedMeters
        }
    }

    public var sessionsDone: Int
    public var sessionsPlanned: Int
    public var runMeters: Double
    public var plannedRunMeters: Double
    public var runs: Int
    public var lifts: Int
    /// This week's load against an average week (1 = usual), when known.
    public var loadRatio: Double?
    public var newBests: [String]
    /// One sentence on how the week went.
    public var headline: String

    public var completion: Double { sessionsPlanned > 0 ? Double(sessionsDone) / Double(sessionsPlanned) : 0 }

    /// - Parameters:
    ///   - planned: this week's planned sessions (skipped ones count as planned, not done).
    ///   - runMeters, runs, lifts: what was actually done this week (planned or not).
    public static func make(planned: [Session], runMeters: Double, runs: Int, lifts: Int,
                            loadRatio: Double?, newBests: [String]) -> WeekReview {
        let counted = planned.filter { $0.discipline != .crossTraining || $0.status == .completed }
        let done = counted.filter { $0.status == .completed }.count
        let plannedMeters = planned.filter { $0.discipline == .run }.reduce(0) { $0 + $1.plannedMeters }
        var review = WeekReview(sessionsDone: done, sessionsPlanned: counted.count, runMeters: runMeters,
                                plannedRunMeters: plannedMeters, runs: runs, lifts: lifts, loadRatio: loadRatio,
                                newBests: newBests, headline: "")
        review.headline = headline(for: review)
        return review
    }

    static func headline(for review: WeekReview) -> String {
        guard review.sessionsPlanned > 0 else {
            return review.runs + review.lifts > 0 ? "\(review.runs + review.lifts) sessions this week." : "A rest week."
        }
        let done = "\(review.sessionsDone) of \(review.sessionsPlanned) sessions"
        let best = review.newBests.isEmpty ? "" : " And a new best: \(review.newBests[0])."
        if review.sessionsDone >= review.sessionsPlanned {
            return "Every session done. A complete week." + best
        }
        if review.completion >= 0.75 {
            return "Solid week: \(done) done." + best
        }
        if let ratio = review.loadRatio, ratio > 1.3 {
            return "\(done), but your load was well above usual. Keep the easy days easy next week." + best
        }
        if review.completion >= 0.4 {
            return "\(done) done. Life happens; next week is a fresh start." + best
        }
        return "A lighter week: \(done). Your plan carries on from here, no need to catch up." + best
    }
}
