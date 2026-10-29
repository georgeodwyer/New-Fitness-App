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
        prioritiseLifts: Bool = false,
        keepLegSessions: Bool? = nil,
        longRunDay: Weekday? = nil
    ) -> Result {
        // When a leg session fits nowhere, ease a hard run to keep it (lifting goals, Hyrox),
        // or drop the leg session (running goals).
        let easeRunsForLegs = keepLegSessions ?? prioritiseLifts
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
            let chosen = longRunDay.flatMap { allowed.contains($0) ? $0 : nil }
            let preferred = chosen ?? [Weekday.sunday, .saturday].first { allowed.contains($0) } ?? allowed.last
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
                        && !(BalanceRules.current.scheduling.noLowerBodyLiftDayBeforeHardRun
                             && (state.lifts[day.previous]?.focus.loadsLowerBody ?? false))
                        && !(BalanceRules.current.scheduling.noLowerBodyLiftOnHardRunDay
                             && (state.lifts[day]?.focus.loadsLowerBody ?? false))
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

        // Gym sessions, laid out together: every way of putting them on the free days is scored,
        // so sessions working the same muscles are never on back-to-back days if it can be helped,
        // the split keeps its order where it can, and there's still room for the runs.
        func placeLifts() {
            let qualityCount = remainingRuns.filter(\.isQuality).count
            let easyCount = remainingRuns.count - qualityCount
            var best: (days: [Weekday?], score: Double)?
            var chosen: [Weekday?] = []
            func search(_ index: Int, _ trial: inout State) {
                if index == lifts.count {
                    let score = trial.liftLayoutScore(lifts, days: chosen, qualityRuns: qualityCount, easyRuns: easyCount)
                    if best == nil || score > best!.score + 1e-9 { best = (chosen, score) }
                    return
                }
                let lift = lifts[index]
                let options = trial.days.filter { trial.canPlaceLift(lift, on: $0) }
                for day in options {
                    trial.lifts[day] = lift
                    chosen.append(day)
                    search(index + 1, &trial)
                    chosen.removeLast()
                    trial.lifts[day] = nil
                }
                if options.isEmpty {
                    // No day for it: left out (or made room for below).
                    chosen.append(nil)
                    search(index + 1, &trial)
                    chosen.removeLast()
                }
            }
            var trial = state
            search(0, &trial)
            let layout = best?.days ?? Array(repeating: nil, count: lifts.count)
            for (lift, day) in zip(lifts, layout) {
                if let day {
                    state.addLift(lift, on: day)
                } else if easeRunsForLegs, lift.focus.loadsLowerBody, let room = state.roomByEasingHardRun(for: lift) {
                    // Keep the leg session: one of several hard runs becomes easy instead.
                    let eased = state.runs[room.eased] ?? .intervals
                    state.addRun(.easy, on: room.eased)
                    state.addLift(lift, on: room.day)
                    notes.append("Your \(SessionKind.run(eased).displayName.lowercased()) became an easy run this week to make room for \(lift.name), so your legs aren't worked on a hard-run day.")
                } else {
                    notes.append("\(lift.name) was left out this week: there was no day that wouldn't tire your legs before a hard run or long run.")
                }
            }
        }

        // The long run keeps its day; the gym week goes next and the other runs fit around it.
        placeLongRun()
        placeLifts()
        placeQualityRuns()
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
                notes.append("One easy run was dropped this week to keep enough recovery around your hard sessions.")
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
                let rules = BalanceRules.current.scheduling
                if rules.noLowerBodyLiftDayBeforeHardRun, byDay[day.next]?.contains(where: { $0.isHardRun }) == true {
                    problems.append("lower-body lift on \(day.shortName) before a hard run")
                }
                if rules.noLowerBodyLiftOnLongRunDay, items.contains(where: { $0.item == .run(.long) }) {
                    problems.append("lower-body lift on the long-run day")
                }
                if rules.noLowerBodyLiftOnHardRunDay, items.contains(where: { $0.isHardRun }) {
                    problems.append("lower-body lift on a hard-run day (\(day.shortName))")
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
                let rules = BalanceRules.current.scheduling
                if rules.noLowerBodyLiftDayBeforeHardRun && isHardRunDay(day.next) { return false }
                if rules.noLowerBodyLiftOnLongRunDay && runs[day] == .long { return false }
                if rules.noLowerBodyLiftOnHardRunDay && isHardRunDay(day) { return false }
            }
            return true
        }

        func liftScore(_ lift: StrengthSessionTemplate, on day: Weekday) -> Double {
            var score = 0.0
            if let run = runs[day] {
                // Hard days hard: pair lower-body lifting with a quality run (lift after the run).
                if run.isQuality {
                    score += lift.focus.loadsLowerBody && BalanceRules.current.scheduling.pairLowerBodyLiftsWithHardRuns ? 4 : 1
                }
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

        /// How good a layout of the week's gym sessions is (`days[i]` for `lifts[i]`, nil = left out).
        func liftLayoutScore(_ lifts: [StrengthSessionTemplate], days layout: [Weekday?], qualityRuns: Int, easyRuns: Int) -> Double {
            var score = 0.0
            let placed = zip(lifts, layout).compactMap { lift, day in day.map { (lift, $0) } }
            score -= 30 * Double(layout.count - placed.count)
            for (lift, day) in placed {
                score += runs[day] == nil ? 3 : (runs[day]?.isQuality == true && lift.focus.loadsLowerBody ? 2 : 1)
                // Legs are tired the day after the long run.
                if lift.focus.loadsLowerBody && runs[day.previous] == .long { score -= 2 }
                // Spread gym days out a little.
                let spacing = placed.filter { $0.1 != day }.map { $0.1.circularDistance(to: day) }.min() ?? 3
                score += 0.3 * Double(min(spacing, 3))
            }
            // The same muscles on back-to-back days (also Sunday into Monday): avoided if at all possible.
            for (i, a) in placed.enumerated() {
                for b in placed[(i + 1)...] where a.1.circularDistance(to: b.1) == 1 && a.0.sharesMuscles(with: b.0) {
                    score -= 20
                }
            }
            // The split's order (Push, Pull, Legs…) through the week where it fits.
            for i in placed.indices.dropLast() where placed[i].1 < placed[i + 1].1 { score += 0.4 }
            // Room left for the runs.
            var free = 0, withLift = 0, nonLegFree = 0
            for day in days where runs[day] == nil {
                let afterLegs = placed.contains { $0.1 == day.previous && $0.0.focus.loadsLowerBody }
                let lift = placed.first { $0.1 == day }?.0
                if lift == nil { free += 1 } else { withLift += 1 }
                if !afterLegs && !(lift?.focus.loadsLowerBody ?? false) {
                    if lift == nil { nonLegFree += 1 }
                }
            }
            let doublesLeft = max(0, doubleDays - placed.filter { runs[$0.1] != nil }.count)
            let hardRoom = nonLegFree + doublesLeft
            score -= 8 * Double(max(0, qualityRuns - hardRoom))
            score -= 4 * Double(max(0, qualityRuns + easyRuns - free - min(withLift, doublesLeft)))
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

        /// When a lower-body lift fits nowhere, the hard run (not the long run) whose easing frees the
        /// best day. Only offered when another tempo or intervals run stays hard that week.
        func roomByEasingHardRun(for lift: StrengthSessionTemplate) -> (day: Weekday, eased: Weekday)? {
            let workouts = days.filter { runs[$0] == .tempo || runs[$0] == .intervals }
            guard workouts.count >= 2 else { return nil }
            var best: (day: Weekday, eased: Weekday, score: Double)?
            for eased in workouts {
                var trial = self
                trial.runs[eased] = .easy
                for day in days where trial.canPlaceLift(lift, on: day) {
                    let score = trial.liftScore(lift, on: day)
                    if best == nil || score > best!.score { best = (day, eased, score) }
                }
            }
            return best.map { ($0.day, $0.eased) }
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

// MARK: - Muscles worked

/// The muscle areas a gym session works hard, so two sessions on the same muscles aren't put on
/// back-to-back days. Push and Pull don't overlap (that's the point of the split); Upper,
/// Shoulders & arms and Full body overlap both.
enum MuscleArea: Hashable {
    case chest, back, shoulders, biceps, triceps, legs
}

extension StrengthSessionTemplate {
    var muscleAreas: Set<MuscleArea> {
        switch focus {
        case .push: return [.chest, .shoulders, .triceps]
        case .pull: return [.back, .biceps]
        case .legs, .lower: return [.legs]
        case .fullBody: return [.chest, .back, .shoulders, .legs]
        case .upper:
            // An upper day is read from its exercises (Shoulders & arms has no chest or back).
            var areas = Set<MuscleArea>()
            for slot in slots { areas.formUnion(Self.areas(for: slot)) }
            return areas.isEmpty ? [.chest, .back, .shoulders, .biceps, .triceps] : areas
        }
    }

    func sharesMuscles(with other: StrengthSessionTemplate) -> Bool {
        !muscleAreas.isDisjoint(with: other.muscleAreas)
    }

    private static func areas(for slot: ExerciseSlot) -> Set<MuscleArea> {
        switch slot.pattern {
        case "horizontalPush": return [.chest, .triceps]
        case "verticalPush": return [.shoulders, .triceps]
        case "horizontalPull", "verticalPull": return [.back, .biceps]
        case "arms": return [.biceps, .triceps]
        case "squat", "lunge", "hinge", "hingeAccessory", "calf": return [.legs]
        case "core", "antiRotation": return []
        default: break
        }
        let name = (slot.exerciseName ?? "").lowercased()
        if name.isEmpty { return [] }
        if name.contains("leg ") || name.contains("squat") || name.contains("lunge") || name.contains("calf")
            || name.contains("deadlift") || name.contains("hip thrust") || name.contains("step-up") { return [.legs] }
        if name.contains("curl") { return [.biceps] }
        if name.contains("tricep") || name.contains("skull") || name.contains("close-grip") || name.contains("dip") { return [.triceps] }
        if name.contains("lateral") || name.contains("shoulder") || name.contains("overhead press") || name.contains("arnold")
            || name.contains("rear delt") || name.contains("face pull") || name.contains("upright") { return [.shoulders] }
        if name.contains("bench") || name.contains("chest") || name.contains("fly") || name.contains("push-up") { return [.chest, .triceps] }
        if name.contains("row") || name.contains("pulldown") || name.contains("pull-up") || name.contains("chin-up")
            || name.contains("pullover") { return [.back, .biceps] }
        return []
    }
}
