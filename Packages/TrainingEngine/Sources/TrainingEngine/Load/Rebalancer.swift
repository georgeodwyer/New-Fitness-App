import Foundation

/// A session in the current week, as the rebalancer sees it.
public struct WeekSession: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var slot: SessionSlot
    public var kind: SessionKind
    public var isKey: Bool
    public var status: SessionStatus
    public var title: String
    public var summary: String
    public var durationMinutes: Double
    public var effort: Double
    public var runStructure: RunStructure?
    public var strength: StrengthPrescription?
    /// Set once the session has been changed by the rebalancer (it won't be changed again).
    public var changeReason: String?

    public init(id: UUID, date: Date, slot: SessionSlot, kind: SessionKind, isKey: Bool, status: SessionStatus = .planned,
                title: String, summary: String = "", durationMinutes: Double, effort: Double,
                runStructure: RunStructure? = nil, strength: StrengthPrescription? = nil, changeReason: String? = nil) {
        self.id = id
        self.date = date
        self.slot = slot
        self.kind = kind
        self.isKey = isKey
        self.status = status
        self.title = title
        self.summary = summary
        self.durationMinutes = durationMinutes
        self.effort = effort
        self.runStructure = runStructure
        self.strength = strength
        self.changeReason = changeReason
    }

    var isHardRun: Bool {
        if case .run(let type) = kind { return type.isQuality }
        return false
    }

    var loadsLowerBody: Bool {
        if case .strength(let focus) = kind { return focus.loadsLowerBody && status != .swapped }
        return false
    }

    var isRun: Bool { kind.discipline == .run }

    /// Hard runs, long runs and lifts are moved to a later day if skipped; easy sessions
    /// are just dropped.
    var movesWhenSkipped: Bool {
        isHardRun || kind.discipline == .strength
    }
}

/// A change to apply to one session, with a one-sentence explanation for the user.
/// Why the plan changed (shown in the change history with the numbers behind it).
public enum ChangeCause: String, Codable, Sendable, CaseIterable {
    /// The athlete skipped a session (a hard session or lift may move to another day).
    case skipped
    /// The athlete chose a lighter alternative.
    case swapped
    /// The acute:chronic load ratio went above the optimal range.
    case highLoad
    /// The check-in (and body signals like resting HR) showed poor recovery.
    case poorRecovery
    /// The recovery score was low (or the athlete took the lighter version on a fair day).
    case lowRecovery
    /// The athlete moved a session to another day.
    case moved
    case other
}

public struct Adjustment: Equatable, Sendable {
    public var session: WeekSession
    public var explanation: String
    public var cause: ChangeCause

    public init(session: WeekSession, explanation: String, cause: ChangeCause = .other) {
        self.session = session
        self.explanation = explanation
        self.cause = cause
    }
}

/// A lighter alternative the user can swap a session for.
public struct SwapOption: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var systemImage: String
    /// The replacement session (same id as the original).
    public var replacement: WeekSession
    public var explanation: String
}

/// Rebalances the rest of the week after skips, swaps, high load or poor recovery:
/// missed sessions aren't stacked, skipped hard sessions and lifts are moved if there's a
/// sensible slot, and load is reduced when the acute:chronic ratio is high.
public enum Rebalancer {
    public struct Context: Sendable {
        public var trainingDays: [Weekday]
        public var zones: PaceZones
        public var units: UnitSystem
        public var calendar: Calendar
        public var today: Date

        public init(trainingDays: [Weekday], zones: PaceZones, units: UnitSystem, calendar: Calendar, today: Date) {
            self.trainingDays = trainingDays
            self.zones = zones
            self.units = units
            self.calendar = calendar
            self.today = today
        }
    }

    // MARK: - Skip

    /// Skips a session. A hard run, long run or lift is moved to a suitable later day this
    /// week if one exists (taking the place of an easy session of the same discipline where
    /// possible); otherwise it's dropped, as are easy sessions. Nothing is ever doubled up to
    /// "make up" for a skip.
    public static func skip(_ id: UUID, week: [WeekSession], context: Context) -> [Adjustment] {
        guard var skipped = week.first(where: { $0.id == id }) else { return [] }
        let name = skipped.title.lowercased()
        skipped.status = .skipped

        guard skipped.movesWhenSkipped else {
            let reason = "Skipped your \(name). It won't be squeezed in elsewhere, so the rest of the week stays balanced."
            skipped.changeReason = reason
            return [Adjustment(session: skipped, explanation: reason, cause: .skipped)]
        }

        // Try to move the session to a later day this week.
        let calendar = context.calendar
        let today = calendar.startOfDay(for: context.today)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfISOWeek(for: skipped.date)) ?? today
        let remaining = week.filter { $0.id != id && $0.status == .planned }
        // Later days only: after today and after the session's own day.
        let dayAfterToday = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let dayAfterSession = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: skipped.date)) ?? today
        var candidates: [Date] = []
        var day = max(dayAfterToday, dayAfterSession)
        while day < weekEnd {
            if context.trainingDays.contains(calendar.weekday(of: day)) { candidates.append(day) }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? weekEnd
        }

        let weekdayName = { (date: Date) in calendar.weekday(of: date).fullName }

        // 1) Take the place of an easy session of the same discipline.
        for date in candidates {
            let onDay = remaining.filter { calendar.isDate($0.date, inSameDayAs: date) }
            guard let easy = onDay.first(where: { isEasyReplaceable($0, for: skipped) }) else { continue }
            var moved = skipped
            moved.status = .planned
            moved.date = date
            moved.slot = easy.slot
            let others = remaining.filter { $0.id != easy.id } + [moved]
            guard isValid(others, calendar: calendar) else { continue }
            let reason = "Moved your \(name) to \(weekdayName(date)) in place of the \(easy.title.lowercased()), so you keep it without adding extra load."
            moved.changeReason = reason
            var dropped = easy
            dropped.status = .skipped
            dropped.changeReason = "Replaced by your \(name), moved from earlier in the week."
            return [Adjustment(session: moved, explanation: reason, cause: .skipped), Adjustment(session: dropped, explanation: dropped.changeReason ?? "", cause: .skipped)]
        }

        // 2) Use a free training day.
        for date in candidates where !remaining.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            var moved = skipped
            moved.status = .planned
            moved.date = date
            moved.slot = .morning
            guard isValid(remaining + [moved], calendar: calendar) else { continue }
            let reason = "Moved your \(name) to \(weekdayName(date)), a free training day, so you still get it in this week."
            moved.changeReason = reason
            return [Adjustment(session: moved, explanation: reason, cause: .skipped)]
        }

        let reason = "Your \(name) couldn't fit later this week without crowding other hard sessions, so it's been dropped rather than stacked."
        skipped.changeReason = reason
        return [Adjustment(session: skipped, explanation: reason, cause: .skipped)]
    }

    private static func isEasyReplaceable(_ candidate: WeekSession, for key: WeekSession) -> Bool {
        guard !candidate.movesWhenSkipped, candidate.changeReason == nil else { return false }
        switch (candidate.kind, key.kind) {
        case (.run(let type), .run): return type == .easy || type == .recovery
        case (.crossTraining, .run): return true
        case (.strength, .strength): return true
        case (.mobility, _): return true
        default: return false
        }
    }

    /// Interference rules for a set of planned sessions.
    static func isValid(_ sessions: [WeekSession], calendar: Calendar) -> Bool {
        let planned = sessions.filter { $0.status == .planned }
        let byDay = Dictionary(grouping: planned) { calendar.startOfDay(for: $0.date) }
        for (day, items) in byDay {
            if items.filter(\.isRun).count > 1 { return false }
            if items.count > 2 { return false }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let previous = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let hardHere = items.contains(where: \.isHardRun)
            if items.contains(where: \.loadsLowerBody) {
                if byDay[next]?.contains(where: \.isHardRun) == true { return false }
                if items.contains(where: { $0.kind == .run(.long) }) { return false }
            }
            // No back-to-back hard runs.
            if hardHere, byDay[next]?.contains(where: \.isHardRun) == true || byDay[previous]?.contains(where: \.isHardRun) == true {
                return false
            }
        }
        return true
    }

    // MARK: - Swap

    /// Lighter alternatives for a session.
    public static func swapOptions(for session: WeekSession, context: Context) -> [SwapOption] {
        let name = session.title.lowercased()
        var options: [SwapOption] = []
        let rules = BalanceRules.current.rebalancing
        let minutes = max(rules.minimumEasyRunMinutes, session.durationMinutes)

        switch session.kind {
        case .run(let type):
            let easyMinutes = type == .long ? (minutes * rules.easedLongRunFactor).rounded() : min(minutes, rules.easedRunMaxMinutes)
            options.append(easyRun(minutes: easyMinutes, from: session, context: context,
                                   explanation: "Swapped your \(name) for an easy \(Int(easyMinutes))-minute run: aerobic work without the strain."))
            options.append(crossTraining(minutes: min(rules.easedRunMaxMinutes, minutes), from: session,
                                         explanation: "Swapped your \(name) for low-impact cardio to give your legs a break from pounding."))
        case .strength:
            if let strength = session.strength {
                var lighter = session
                lighter.strength = StrengthPrescription(exercises: strength.exercises.map { exercise in
                    var copy = exercise
                    copy.sets = max(1, Int((Double(exercise.sets) * rules.reducedLiftSetsFactor).rounded()))
                    return copy
                })
                lighter.durationMinutes = max(rules.minimumEasyRunMinutes, (session.durationMinutes * rules.reducedLiftSetsFactor / 5).rounded() * 5)
                lighter.effort = max(3, session.effort - 2)
                lighter.title = session.title + " (reduced)"
                lighter.summary = "Same exercises and weights, about 40% fewer sets"
                lighter.status = .swapped
                let reason = "Swapped to a reduced-volume \(name): same weights, fewer sets, so you keep your strength with less fatigue."
                lighter.changeReason = reason
                options.append(SwapOption(id: "reduced", title: "Reduced-volume session", detail: lighter.summary,
                                          systemImage: "dumbbell", replacement: lighter, explanation: reason))
            }
        case .crossTraining, .mobility:
            break
        }
        options.append(mobility(from: session, explanation: "Swapped your \(name) for a mobility session to recover."))
        return options
    }

    private static func easyRun(minutes: Double, from session: WeekSession, context: Context, explanation: String) -> SwapOption {
        let easyPace = context.zones.typicalPace(for: .easy)
        let meters = RunBuilder.tidy(minutes * 60 / easyPace.secondsPerKm * 1000)
        var replacement = session
        replacement.kind = .run(.easy)
        replacement.title = "Easy Run"
        replacement.runStructure = RunBuilder.steady(.easy, distanceMeters: meters, zones: context.zones)
        replacement.strength = nil
        replacement.durationMinutes = minutes
        replacement.effort = 3
        replacement.summary = String(format: "%.1f", Units.distance(meters: meters, in: context.units)) + " " + Units.distanceUnitLabel(context.units) + " easy"
        replacement.status = .swapped
        replacement.changeReason = explanation
        return SwapOption(id: "easyRun", title: "Easy run", detail: "\(Int(minutes)) min at conversational pace",
                          systemImage: "figure.run", replacement: replacement, explanation: explanation)
    }

    private static func crossTraining(minutes: Double, from session: WeekSession, explanation: String) -> SwapOption {
        var replacement = session
        replacement.kind = .crossTraining
        replacement.title = SessionKind.crossTraining.displayName
        replacement.summary = "\(Int(minutes)) min easy cycling, cross-trainer or brisk walk"
        replacement.runStructure = nil
        replacement.strength = nil
        replacement.durationMinutes = minutes
        replacement.effort = 3
        replacement.status = .swapped
        replacement.changeReason = explanation
        return SwapOption(id: "crossTraining", title: "Low-impact cardio", detail: "Cycling, cross-trainer or a brisk walk",
                          systemImage: "bicycle", replacement: replacement, explanation: explanation)
    }

    private static func mobility(from session: WeekSession, explanation: String) -> SwapOption {
        var replacement = session
        replacement.kind = .mobility
        replacement.title = SessionKind.mobility.displayName
        replacement.summary = "20 min stretching and mobility"
        replacement.runStructure = nil
        replacement.strength = nil
        replacement.durationMinutes = 20
        replacement.effort = 2
        replacement.status = .swapped
        replacement.changeReason = explanation
        return SwapOption(id: "mobility", title: "Mobility", detail: "20 min of stretching and mobility work",
                          systemImage: "figure.flexibility", replacement: replacement, explanation: explanation)
    }

    // MARK: - Load & recovery

    /// Lightens the next few days when load is spiking or recovery is poor:
    /// the next hard session becomes easier, and (for a load spike) remaining easy runs
    /// this week are shortened.
    public static func adjustForLoad(week: [WeekSession], status: LoadStatus, checkIn: RecoveryCheckIn?, context: Context) -> [Adjustment] {
        let poorRecovery = checkIn?.isPoor ?? false
        guard status == .high || poorRecovery else { return [] }
        let calendar = context.calendar
        let today = calendar.startOfDay(for: context.today)
        let rules = BalanceRules.current.rebalancing
        let soon = calendar.date(byAdding: .day, value: rules.easeHardSessionWithinDays, to: today) ?? today
        let upcoming = week
            .filter { $0.status == .planned && $0.changeReason == nil && $0.date >= today }
            .sorted { $0.date < $1.date }
        let why = status == .high ? "your training load has spiked" : "your score shows you're not fully recovered"
        let cause: ChangeCause = status == .high ? .highLoad : .poorRecovery
        var adjustments: [Adjustment] = []

        // 1) Ease the next hard session in the next three days.
        if let hard = upcoming.first(where: { $0.date < soon && ($0.isHardRun || $0.kind.discipline == .strength) }) {
            let options = swapOptions(for: hard, context: context)
            let preferred = hard.isHardRun ? options.first { $0.id == "easyRun" } : options.first { $0.id == "reduced" }
            if var replacement = preferred?.replacement {
                let reason = "Eased your \(hard.title.lowercased()) because \(why)."
                replacement.changeReason = reason
                adjustments.append(Adjustment(session: replacement, explanation: reason, cause: cause))
            }
        }

        // 2) For a load spike, trim the remaining easy runs this week by 20%.
        if status == .high {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: calendar.startOfISOWeek(for: today)) ?? today
            for session in upcoming where session.date < weekEnd && session.kind == .run(.easy)
                && !adjustments.contains(where: { $0.session.id == session.id }) {
                var shorter = session
                let minutes = max(rules.minimumEasyRunMinutes, (session.durationMinutes * rules.highLoadEasyRunFactor / 5).rounded() * 5)
                let easyPace = context.zones.typicalPace(for: .easy)
                let meters = RunBuilder.tidy(minutes * 60 / easyPace.secondsPerKm * 1000)
                shorter.durationMinutes = minutes
                shorter.runStructure = RunBuilder.steady(.easy, distanceMeters: meters, zones: context.zones)
                shorter.summary = String(format: "%.1f", Units.distance(meters: meters, in: context.units)) + " " + Units.distanceUnitLabel(context.units)
                let reason = "Shortened your easy run to \(Int(minutes)) minutes because \(why)."
                shorter.changeReason = reason
                adjustments.append(Adjustment(session: shorter, explanation: reason, cause: cause))
            }
        }
        return adjustments
    }

    // MARK: - Recovery taper

    /// How today's recovery score changes today's sessions: Low eases hard sessions
    /// automatically, Fair offers a lighter version, Good or Great leaves the plan alone.
    public enum RecoveryTaper: Equatable, Sendable {
        case none, offer, ease

        public init(_ recovery: RecoveryScore?) {
            switch recovery?.band {
            case .low?: self = .ease
            case .fair?: self = .offer
            default: self = .none
            }
        }
    }

    /// Whether a session gets a lighter version on a low or fair recovery day: today's hard
    /// runs (tempo, intervals, long) and gym sessions that haven't been changed yet.
    public static func canTaper(_ session: WeekSession, context: Context) -> Bool {
        guard session.status == .planned, session.changeReason == nil,
              context.calendar.isDate(session.date, inSameDayAs: context.today) else { return false }
        return session.isHardRun || (session.kind.discipline == .strength && session.strength != nil)
    }

    /// The lighter version of a session for a low or fair recovery day: a hard run becomes an
    /// easy run (a long run shortened), a gym session keeps its weights with one set fewer
    /// per exercise.
    public static func lighterVersion(of session: WeekSession, recovery: RecoveryScore, context: Context) -> SwapOption? {
        guard canTaper(session, context: context) else { return nil }
        let name = session.title.lowercased()
        let score = Int(recovery.score)
        let level = recovery.band == .low ? "low" : "fair"
        let rules = BalanceRules.current.rebalancing
        if case .run(let type) = session.kind {
            let minutes = max(rules.minimumEasyRunMinutes, session.durationMinutes)
            let easyMinutes = type == .long ? (minutes * rules.easedLongRunFactor).rounded() : min(minutes, rules.easedRunMaxMinutes)
            var option = easyRun(minutes: easyMinutes, from: session, context: context,
                                 explanation: "Eased your \(name) to an easy \(Int(easyMinutes))-minute run because your recovery is \(level) today (\(score)).")
            option.id = "lighter"
            option.title = "Lighter version"
            return option
        }
        guard let strength = session.strength else { return nil }
        var lighter = session
        lighter.strength = StrengthPrescription(exercises: strength.exercises.map { exercise in
            var copy = exercise
            copy.sets = max(1, exercise.sets - 1)
            return copy
        })
        let removed = strength.exercises.filter { $0.sets > 1 }.count
        let fullSets = max(1, strength.exercises.reduce(0) { $0 + $1.sets })
        let share = Double(fullSets - removed) / Double(fullSets)
        lighter.durationMinutes = max(rules.minimumEasyRunMinutes, (session.durationMinutes * share / 5).rounded() * 5)
        lighter.effort = max(3, session.effort - 1)
        lighter.title = session.title + " (lighter)"
        lighter.summary = "Same exercises and weights, one set fewer each"
        lighter.status = .swapped
        let reason = "Took a set off each exercise in your \(name) because your recovery is \(level) today (\(score))."
        lighter.changeReason = reason
        return SwapOption(id: "lighter", title: "Lighter version", detail: lighter.summary, systemImage: "dumbbell",
                          replacement: lighter, explanation: reason)
    }

    /// On a low recovery day, today's hard runs and gym sessions become their lighter versions.
    public static func taperForRecovery(week: [WeekSession], recovery: RecoveryScore?, context: Context) -> [Adjustment] {
        guard let recovery, RecoveryTaper(recovery) == .ease else { return [] }
        return week.compactMap { session in
            lighterVersion(of: session, recovery: recovery, context: context)
                .map { Adjustment(session: $0.replacement, explanation: $0.explanation, cause: .lowRecovery) }
        }
    }

    // MARK: - Move

    /// The result of moving a session: the change, and a heads-up when the new day breaks a
    /// spacing rule (it's still allowed: it's their week).
    public struct Move: Equatable, Sendable {
        public var adjustment: Adjustment
        public var warning: String?
    }

    /// Moves a session to another day at the same time of day. nil when that day already has
    /// two sessions.
    public static func move(_ id: UUID, to day: Date, week: [WeekSession], context: Context) -> Move? {
        guard var session = week.first(where: { $0.id == id }) else { return nil }
        let calendar = context.calendar
        let target = calendar.startOfDay(for: day)
        guard !calendar.isDate(session.date, inSameDayAs: target) else { return nil }
        let others = week.filter { $0.id != id && $0.status == .planned && calendar.isDate($0.date, inSameDayAs: target) }
        guard others.count < 2 else { return nil }
        let timeOfDay = session.date.timeIntervalSince(calendar.startOfDay(for: session.date))
        session.date = target.addingTimeInterval(timeOfDay)
        // Morning and evening: if the slot is taken, take the other one.
        if others.contains(where: { $0.slot == session.slot }) {
            session.slot = session.slot == .morning ? .evening : .morning
        }
        let dayName = calendar.weekday(of: target).fullName
        // No changeReason: a session the athlete moved can still be eased later on.
        let reason = "You moved your \(session.title.lowercased()) to \(dayName)."
        var after = week.filter { $0.id != id }
        after.append(session)
        var warning: String?
        if others.contains(where: \.isRun) && session.isRun {
            warning = "That day already has a run, so you'll have two runs on \(dayName)."
        } else if !isValid(after, calendar: calendar) {
            warning = "Heads up: this puts hard sessions close together (or a leg day before a hard run). Fine now and then; keep the easy days easy around it."
        }
        return Move(adjustment: Adjustment(session: session, explanation: reason, cause: .moved), warning: warning)
    }
}
