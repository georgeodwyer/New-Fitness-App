import Foundation

/// A session placed on a weekday.
public struct Placement: Equatable, Sendable {
    public enum Item: Equatable, Sendable {
        case run(RunSessionType)
        case lift(StrengthSessionTemplate)
    }

    public var weekday: Weekday
    public var slot: SessionSlot
    public var item: Item

    public var isHardRun: Bool {
        if case .run(let type) = item { return type.isQuality }
        return false
    }

    public var loadsLowerBody: Bool {
        if case .lift(let template) = item { return template.focus.loadsLowerBody }
        return false
    }
}

/// Places a week's runs and lifts onto the user's training days while managing
/// interference between running and lifting:
/// - at most one run and one lift per day, and at most `doubleDays` days with two sessions
/// - no heavy lower-body lifting the day before (within ~24h of) a quality or long run,
///   and none on the long-run day
/// - quality runs spread apart; lower-body lifting paired with hard run days where doubles
///   allow ("hard days hard, easy days easy")
/// - only the user's training days are used (so rest days stay rest days)
public enum WeekScheduler {
    public struct Result: Equatable, Sendable {
        public var placements: [Placement]
        /// One-sentence explanations for anything that couldn't be scheduled.
        public var notes: [String]
    }

    public static func schedule(
        days: [Weekday],
        doubleDays: Int,
        runs: [RunSessionType],
        lifts: [StrengthSessionTemplate],
        prioritiseLifts: Bool = false
    ) -> Result {
        var state = State(days: days.sorted(), doubleDays: doubleDays)
        var notes: [String] = []

        var convertedToEasy = 0
        var remainingRuns = runs

        // Long run at the weekend if possible. It never follows a lower-body lift day
        // (only relevant when lifts were placed first).
        func placeLongRun() {
            guard let longIndex = remainingRuns.firstIndex(of: .long) else { return }
            remainingRuns.remove(at: longIndex)
            let allowed = state.days.filter { day in
                state.runs[day] == nil
                    && state.hasCapacity(on: day)
                    && !(state.lifts[day]?.focus.loadsLowerBody ?? false)
                    && !(state.lifts[day.previous]?.focus.loadsLowerBody ?? false)
            }
            let preferred = [Weekday.sunday, .saturday].first { allowed.contains($0) } ?? allowed.last
            if let day = preferred {
                state.addRun(.long, on: day)
            } else {
                convertedToEasy += 1
                notes.append("Your long run became an easy run this week so it doesn't follow a leg session.")
            }
        }

        // Quality runs, spread as far as possible from other hard runs. If lifting has
        // priority, they also avoid the day after a lower-body session; a quality run with
        // no suitable day becomes an easy run.
        func placeQualityRuns() {
            for type in remainingRuns where type.isQuality {
                let candidates = state.days.filter { day in
                    state.runs[day] == nil
                        && state.hasCapacity(on: day)
                        && !(state.lifts[day.previous]?.focus.loadsLowerBody ?? false)
                }
                let best = candidates.max { a, b in
                    let sa = state.hardRunSpacing(for: a), sb = state.hardRunSpacing(for: b)
                    return sa == sb ? a > b : sa < sb // ties → earlier day
                }
                if let day = best {
                    state.addRun(type, on: day)
                } else {
                    convertedToEasy += 1
                    notes.append("Your \(SessionKind.run(type).displayName.lowercased()) became an easy run this week so it doesn't clash with lifting.")
                }
            }
            remainingRuns.removeAll { $0.isQuality }
        }

        // Lifts, lower-body first because they're the most constrained.
        func placeLifts() {
            let orderedLifts = lifts.enumerated().sorted { lhs, rhs in
                if lhs.element.focus.loadsLowerBody != rhs.element.focus.loadsLowerBody {
                    return lhs.element.focus.loadsLowerBody
                }
                return lhs.offset < rhs.offset
            }.map(\.element)
            for lift in orderedLifts {
                let candidates = state.days.filter { state.canPlaceLift(lift, on: $0) }
                let best = candidates.max { a, b in
                    let sa = state.liftScore(lift, on: a), sb = state.liftScore(lift, on: b)
                    return sa == sb ? a > b : sa < sb
                }
                if let day = best {
                    state.addLift(lift, on: day)
                } else {
                    notes.append("\(lift.name) was left out this week: there was no day that wouldn't tire your legs before a key run.")
                }
            }
        }

        if prioritiseLifts {
            placeLifts()
            placeLongRun()
            placeQualityRuns()
        } else {
            placeLongRun()
            placeQualityRuns()
            placeLifts()
        }
        remainingRuns += Array(repeating: .easy, count: convertedToEasy)

        // Easy runs in the gaps.
        for type in remainingRuns {
            let candidates = state.days.filter { state.runs[$0] == nil && state.hasCapacity(on: $0) }
            let best = candidates.max { a, b in
                let sa = state.easyRunScore(on: a), sb = state.easyRunScore(on: b)
                return sa == sb ? a > b : sa < sb
            }
            if let day = best {
                state.addRun(type, on: day)
            } else {
                notes.append("One easy run was dropped this week to keep enough recovery around your key sessions.")
            }
        }

        return Result(placements: state.placements(), notes: notes)
    }

    /// Rule checks used by tests and by the rebalancer. Empty means the week is valid.
    public static func violations(_ placements: [Placement], days: [Weekday], doubleDays: Int) -> [String] {
        var problems: [String] = []
        let byDay = Dictionary(grouping: placements, by: \.weekday)
        if Set(byDay.keys).count >= 7 { problems.append("no rest day") }
        var doubles = 0
        for (day, items) in byDay {
            if !days.contains(day) { problems.append("\(day.shortName) is not a training day") }
            if items.count > 2 { problems.append("\(day.shortName) has more than two sessions") }
            if items.count == 2 { doubles += 1 }
            if items.filter({ if case .run = $0.item { return true }; return false }).count > 1 {
                problems.append("\(day.shortName) has two runs")
            }
            if items.filter({ if case .lift = $0.item { return true }; return false }).count > 1 {
                problems.append("\(day.shortName) has two lifts")
            }
            let lowerLift = items.contains { $0.loadsLowerBody }
            if lowerLift {
                if byDay[day.next]?.contains(where: { $0.isHardRun }) == true {
                    problems.append("lower-body lift on \(day.shortName) before a key run")
                }
                if items.contains(where: { $0.item == .run(.long) }) {
                    problems.append("lower-body lift on the long-run day")
                }
            }
        }
        if doubles > doubleDays { problems.append("too many double days") }
        return problems
    }

    // MARK: - Working state

    private struct State {
        let days: [Weekday]
        let doubleDays: Int
        var runs: [Weekday: RunSessionType] = [:]
        var lifts: [Weekday: StrengthSessionTemplate] = [:]

        init(days: [Weekday], doubleDays: Int) {
            self.days = days
            self.doubleDays = doubleDays
        }

        var doublesUsed: Int { days.filter { runs[$0] != nil && lifts[$0] != nil }.count }

        func sessionCount(on day: Weekday) -> Int {
            (runs[day] == nil ? 0 : 1) + (lifts[day] == nil ? 0 : 1)
        }

        func hasCapacity(on day: Weekday) -> Bool {
            switch sessionCount(on: day) {
            case 0: return true
            case 1: return doublesUsed < doubleDays
            default: return false
            }
        }

        func isHardRunDay(_ day: Weekday) -> Bool { runs[day]?.isQuality == true }

        var hardDays: [Weekday] { days.filter(isHardRunDay) }

        /// Minimum distance to any existing hard run (7 if none yet).
        func hardRunSpacing(for day: Weekday) -> Int {
            hardDays.map { $0.circularDistance(to: day) }.min() ?? 7
        }

        func canPlaceLift(_ lift: StrengthSessionTemplate, on day: Weekday) -> Bool {
            guard lifts[day] == nil, hasCapacity(on: day) else { return false }
            if lift.focus.loadsLowerBody {
                if isHardRunDay(day.next) { return false }
                if runs[day] == .long { return false }
            }
            return true
        }

        func liftScore(_ lift: StrengthSessionTemplate, on day: Weekday) -> Double {
            var score = 0.0
            if let run = runs[day] {
                // Hard days hard: pair lower-body lifting with a quality run (lift after the run).
                if run.isQuality { score += lift.focus.loadsLowerBody ? 4 : 1 }
            } else {
                score += 3
            }
            // Spread lifting days out.
            let otherLiftDays = lifts.keys
            let spacing = otherLiftDays.map { $0.circularDistance(to: day) }.min() ?? 3
            score += 0.5 * Double(min(spacing, 3))
            // Legs are tired the day after a long or quality run.
            if lift.focus.loadsLowerBody {
                if runs[day.previous] == .long { score -= 2 }
                if isHardRunDay(day.previous) && runs[day.previous] != .long { score -= 1 }
            }
            return score
        }

        func easyRunScore(on day: Weekday) -> Double {
            var score = 0.0
            if lifts[day] == nil {
                score += 3
            } else if lifts[day]?.focus.loadsLowerBody == false {
                score += 1
            } else {
                score += 0.5
            }
            // Easy running the day after a hard day aids recovery.
            if isHardRunDay(day.previous) { score += 0.5 }
            return score
        }

        mutating func addRun(_ type: RunSessionType, on day: Weekday) { runs[day] = type }
        mutating func addLift(_ lift: StrengthSessionTemplate, on day: Weekday) { lifts[day] = lift }

        func placements() -> [Placement] {
            var result: [Placement] = []
            for day in days {
                let run = runs[day]
                let lift = lifts[day]
                if let run {
                    result.append(Placement(weekday: day, slot: .morning, item: .run(run)))
                }
                if let lift {
                    result.append(Placement(weekday: day, slot: run == nil ? .morning : .evening, item: .lift(lift)))
                }
            }
            return result
        }
    }
}
