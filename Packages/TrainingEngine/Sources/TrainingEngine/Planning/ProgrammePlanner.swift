import Foundation

/// Builds plans from the coach's programmes (see `Programme`), sized to the runner:
///
/// - **Weekly volume** = the week's % × the runner's starting volume (their answer in
///   onboarding, within the Rules tab's limits), never more than `maxWeeklyIncrease` above
///   the biggest of the last three weeks, and within the programme's weekly cap.
/// - **Long run**: auto (the Rules share of the week), a % or km, capped by the programme,
///   the Rules tab and, early on, the runner's longest recent run.
/// - **Rep sessions** keep their rep lengths; lower-volume runners get fewer reps so hard
///   running stays a sensible share of the week. An easy warm-up and cool-down are added.
/// - **Other runs** share what's left of the week; distances written in a workout set the
///   shape of the run, not its size.
/// - **The race** is its full distance on race day and isn't counted in the week's %.
/// - Fewer run days than the programme has sessions → recovery and easy runs go first;
///   more → easy runs are added.
enum ProgrammePlanner {
    // MARK: Starting volume

    /// The runner's starting weekly volume.
    static func startVolume(profile: AthleteProfile, programme: Programme, rules: ProgrammeRules) -> Double {
        var start = rules.defaultStartMeters
        if let answer = profile.weeklyRunMeters, answer > 0 {
            start = min(max(answer, rules.minStartMeters), rules.maxStartMeters)
        }
        if let cap = programme.weeklyCapMeters { start = min(start, cap) }
        return start
    }

    /// Runs and lifts a week holds for this programme.
    static func counts(profile: AthleteProfile, programme: Programme, rules: PlanRules) -> (runs: Int, lifts: Int) {
        let mix = MixBuilder.sessionCounts(profile: profile, rules: rules)
        let slots = mix.days.count + mix.doubles
        let runs = max(0, min(max(mix.runs, programme.runsPerWeekMin), programme.runsPerWeekMax, mix.days.count))
        let lifts = max(0, min(mix.lifts, slots - runs))
        return (runs, lifts)
    }

    // MARK: Outline

    private enum Slot {
        case programme(ProgrammeWeek, volumeShare: Double)
        /// The easy week after the programme.
        case recovery
        /// An easy first week, for runners who've just raced and asked for one.
        case easyStart
    }

    /// The runner asked for an easy first week in the last three weeks (so an old answer
    /// doesn't add one to a plan rebuilt months later).
    static func wantsEasyStart(_ profile: AthleteProfile, startMonday: Date) -> Bool {
        guard profile.easyFirstWeek == true, let asked = profile.easyFirstWeekRequestedAt else { return false }
        return startMonday.timeIntervalSince(asked) < 21 * 86_400
    }

    /// The plan's weeks. With a race date, the programme is lined up so its last week is
    /// race week: earlier weeks are skipped if the race is sooner, and the first weeks are
    /// repeated as a lead-in if it's further away. Afterwards (unless the programme stops)
    /// there's an easy recovery week; the programme then repeats (see `nextCycle`).
    static func outline(programme: Programme, profile: AthleteProfile, startMonday: Date, rules: ProgrammeRules,
                        calendar: Calendar) -> PlanOutline {
        let length = programme.weeks.count
        let easyStart = wantsEasyStart(profile, startMonday: startMonday)
        var eventDate: Date?
        var firstWeek = 1
        var leadIn = 0
        if let event = profile.eventDate, event >= startMonday {
            let eventMonday = calendar.startOfISOWeek(for: event)
            // The easy week (if any) comes out of the time before the race.
            let weeksToEvent = max((calendar.dateComponents([.day], from: startMonday, to: eventMonday).day ?? 0) / 7 + 1
                                   - (easyStart ? 1 : 0), 1)
            eventDate = event
            if weeksToEvent >= length {
                leadIn = min(weeksToEvent - length, 40)
            } else {
                firstWeek = length - weeksToEvent + 1
            }
        }

        var slots: [Slot] = easyStart ? [.easyStart] : []
        // Lead-in: the base weeks again at the starting volume, every fourth a little lighter.
        let baseWeeks = programme.weeks.filter { $0.phase == .base && !$0.isDeload }
        let leadPattern = baseWeeks.isEmpty ? Array(programme.weeks.prefix(1)) : baseWeeks
        let firstShare = programme.weeks.first?.volume ?? 1
        for i in 0..<leadIn {
            var week = leadPattern[i % leadPattern.count]
            week.isDeload = i % 4 == 3
            slots.append(.programme(week, volumeShare: week.isDeload ? firstShare * 0.9 : firstShare))
        }
        for week in programme.weeks where week.week >= firstWeek {
            slots.append(.programme(week, volumeShare: week.volume))
        }
        if programme.afterLastWeek != "stop" { slots.append(.recovery) }

        let start = startVolume(profile: profile, programme: programme, rules: rules)
        let weeks = buildWeeks(slots, programme: programme, start: start, target: programme.raceReady(for: profile.runningExperience),
                               startMonday: startMonday, firstIndex: 0, history: [start], cycle: 1, rules: rules, calendar: calendar)
        var outline = PlanOutline(startDate: startMonday, eventDate: eventDate, weeks: weeks)
        outline.programmeGoal = programme.goal
        return outline
    }

    /// The programme again after the recovery week, starting from what the runner has
    /// actually been running and moving towards the race-ready volume as before.
    static func nextCycle(after outline: PlanOutline, programme: Programme, profile: AthleteProfile,
                          recentWeeklyRunMeters: Double?, rules: ProgrammeRules, calendar: Calendar) -> PlanOutline {
        guard let last = outline.weeks.last else { return outline }
        var start = startVolume(profile: profile, programme: programme, rules: rules)
        if let recent = recentWeeklyRunMeters, recent > 0 {
            start = min(max(recent, rules.minStartMeters), rules.maxStartMeters)
            if let cap = programme.weeklyCapMeters { start = min(start, cap) }
        }
        let slots: [Slot] = programme.weeks.map { .programme($0, volumeShare: $0.volume) } + [.recovery]
        let startMonday = calendar.date(byAdding: .day, value: 7, to: last.startDate) ?? last.startDate
        let cycle = (last.programmeCycle ?? 1) + 1
        let history = outline.weeks.suffix(3).map(\.runVolumeMeters)
        var extended = outline
        extended.weeks += buildWeeks(slots, programme: programme, start: start, target: programme.raceReady(for: profile.runningExperience),
                                     startMonday: startMonday, firstIndex: outline.weeks.count, history: history, cycle: cycle,
                                     rules: rules, calendar: calendar)
        return extended
    }

    /// Each week's volume = its % × a base. The base starts at the runner's current volume and
    /// moves towards the race-ready volume: up by the max weekly increase after each normal
    /// week, or down by the ease-down rate each week. Without a race-ready volume the base
    /// stays at their current volume.
    private static func buildWeeks(_ slots: [Slot], programme: Programme, start: Double, target: Double?, startMonday: Date,
                                   firstIndex: Int, history: [Double], cycle: Int, rules: ProgrammeRules,
                                   calendar: Calendar) -> [WeekTarget] {
        var history = history
        var weeks: [WeekTarget] = []
        var previousPhase: TrainingPhase?
        var weekInPhase = 0
        var base = start
        var startedProgramme = false
        var previousWasDeload = false
        for (offset, slot) in slots.enumerated() {
            let phase: TrainingPhase
            var volume: Double
            var programmeWeek: Int?
            var isRecovery = false
            var isPostProgramme = false
            var isEasyStart = false
            switch slot {
            case .programme(let week, let volumeShare):
                if startedProgramme, let target {
                    if base < target, !previousWasDeload {
                        base = min(target, base * (1 + rules.maxWeeklyIncrease))
                    } else if base > target {
                        base = max(target, base * (1 - rules.easeDown))
                    }
                }
                startedProgramme = true
                previousWasDeload = week.isDeload
                phase = week.phase
                volume = base * volumeShare
                programmeWeek = week.week
                isRecovery = week.isDeload
            case .recovery:
                phase = .base
                volume = base * rules.recoveryWeek
                isRecovery = true
                isPostProgramme = true
            case .easyStart:
                phase = .base
                volume = start * rules.easyStart
                isRecovery = true
                isEasyStart = true
            }
            if let cap = programme.weeklyCapMeters { volume = min(volume, cap) }
            // Never more than the allowed increase over the biggest of the last three weeks.
            let recent = history.suffix(3).max() ?? start
            volume = min(volume, recent * (1 + rules.maxWeeklyIncrease))
            history.append(volume)

            if phase == previousPhase { weekInPhase += 1 } else { weekInPhase = 0 }
            previousPhase = phase
            let monday = calendar.date(byAdding: .day, value: offset * 7, to: startMonday) ?? startMonday
            weeks.append(WeekTarget(index: firstIndex + offset, startDate: monday, phase: phase, weekInPhase: weekInPhase,
                                    isRecoveryWeek: isRecovery, runVolumeMeters: volume, programmeWeek: programmeWeek,
                                    programmeCycle: cycle, isPostProgrammeRecovery: isPostProgramme ? true : nil,
                                    isEasyStart: isEasyStart ? true : nil))
        }
        return weeks
    }

    // MARK: A week

    /// A run being sized for the week.
    private struct PlannedRun {
        var session: ProgrammeSession
        var meters: Double = 0
        var structure = RunStructure(segments: [])
        var summary = ""
    }

    static func generateWeek(_ index: Int, outline: PlanOutline, programme: Programme, profile: AthleteProfile,
                             templates: TemplateLibrary, workingWeights: [String: Double], notBefore: Date?,
                             calendar: Calendar) -> GeneratedWeek? {
        guard outline.weeks.indices.contains(index) else { return nil }
        let week = outline.weeks[index]
        let rules = templates.programmes.rules(for: profile.runningExperience)
        let planRules = templates.rules
        let zones = PaceZones(profile: profile)
        let isPostProgramme = week.isPostProgrammeRecovery == true || week.isEasyStart == true
        let programmeWeek = week.programmeWeek.flatMap(programme.week)
        let strengthEmphasis = isPostProgramme ? "light" : (programmeWeek?.strength ?? "normal")
        var notes: [String] = []
        if let note = programmeWeek?.note { notes.append(note) }
        if week.isEasyStart == true {
            notes.append("Easy week after your race: easy running only, then your programme starts.")
        } else if isPostProgramme {
            notes.append("Recovery week: easy running only before the programme starts again.")
        }

        // Sessions, fitted to the runner's run days.
        let mix = MixBuilder.sessionCounts(profile: profile, rules: planRules)
        let weekCounts = Self.counts(profile: profile, programme: programme, rules: planRules)
        var sessions = isPostProgramme ? [] : programme.sessions(inWeek: week.programmeWeek ?? 1)
        let written = sessions.count
        sessions = fit(sessions, to: weekCounts.runs)
        if sessions.count < written {
            notes.append("This week has \(sessions.count) runs to fit your \(mix.days.count) training days, so the easiest runs were left out.")
        }
        // A race only happens on race day: without a race date it's a time trial.
        let hasEventThisWeek = outline.eventDate.map { event in
            event >= week.startDate && event < (calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? event)
        } ?? false

        let weekMeters = week.runVolumeMeters
        let shortest = rules.shortestRunMeters

        // Long run cap: the programme, the Rules tab and, early on, their longest recent run.
        var longCap = min(programme.longRunCapMeters, rules.longestRunMeters)
        if let longest = profile.longestRecentRunMeters, longest > 0, (week.programmeCycle ?? 1) == 1 {
            longCap = min(longCap, max(longest * pow(1.1, Double(index + 1)), shortest))
        }

        let context = WeekContext(weekMeters: weekMeters, shortest: shortest, longestRun: rules.longestRunMeters,
                                  longShare: rules.longRunShare, longCap: longCap, longSpec: programmeWeek?.longRun ?? .auto,
                                  raceMeters: programme.raceDistanceMeters ?? 21097.5, raceZone: programme.racePaceZone,
                                  raceLabel: hasEventThisWeek ? "race" : "time trial", programmeName: programme.name, zones: zones,
                                  rules: rules)
        var runs = allocate(sessions, context: context)
        // Volume left over (easy runs were capped) and a free day: add an easy run.
        let room = min(programme.runsPerWeekMax, mix.days.count)
        for _ in 0..<2 {
            let planned = runs.filter { !$0.session.isRace }.reduce(0) { $0 + $1.meters }
            guard weekMeters - planned > shortest * 1.5, sessions.count < room else { break }
            sessions.append(easySession(order: (sessions.map(\.order).max() ?? 0) + 1))
            runs = allocate(sessions, context: context)
        }

        // 4) Days: the usual scheduler, then the race moved to race day.
        let slots = mix.days.count + mix.doubles
        let liftCount = strengthEmphasis == "none" ? 0 : max(0, min(weekCounts.lifts, slots - runs.count))
        let lifts = templates.liftTemplates(for: profile, count: liftCount)
        let schedule = WeekScheduler.schedule(days: mix.days, doubleDays: mix.doubles, runs: runs.map(\.session.runType), lifts: lifts,
                                              prioritiseLifts: false)
        notes += schedule.notes

        var pool = runs
        var assigned: [(placement: Placement, run: PlannedRun)] = []
        var liftPlacements: [Placement] = []
        // Hard placements first, so the session that gets eased (if any) is the least specific one:
        // a Hyrox compromised run keeps its hard slot ahead of plain intervals.
        let ordered = schedule.placements.sorted { a, b in
            if a.isHardRun != b.isHardRun { return a.isHardRun }
            return a.weekday < b.weekday
        }
        func match(_ type: RunSessionType) -> Int? {
            let same = pool.indices.filter { pool[$0].session.runType == type }
            return same.first { pool[$0].session.hasStationWork } ?? same.first
        }
        for placement in ordered {
            switch placement.item {
            case .run(let type):
                if let i = match(type) {
                    assigned.append((placement, pool.remove(at: i)))
                } else if !pool.isEmpty {
                    // The scheduler turned a hard run into an easy one to keep it away from lifting.
                    var run = pool.removeFirst()
                    run.session = easySession(order: run.session.order)
                    let built = flexible(run.session, meters: run.meters, zones: zones)
                    run.structure = built.structure
                    run.summary = built.summary
                    assigned.append((placement, run))
                }
            case .lift:
                liftPlacements.append(placement)
            }
        }
        assigned.sort { $0.placement.weekday < $1.placement.weekday }
        liftPlacements.sort { $0.weekday < $1.weekday }
        if hasEventThisWeek, let event = outline.eventDate, let raceIndex = assigned.firstIndex(where: { $0.run.session.isRace }) {
            let raceDay = calendar.weekday(of: event)
            let current = assigned[raceIndex].placement.weekday
            if current != raceDay {
                if let other = assigned.firstIndex(where: { $0.placement.weekday == raceDay }) {
                    assigned[other].placement.weekday = current
                }
                assigned[raceIndex].placement.weekday = raceDay
            }
            // No lifting on race day or the day before.
            liftPlacements.removeAll { $0.weekday == raceDay || $0.weekday == raceDay.previous }
        }

        // 5) Sessions.
        var generated: [GeneratedSession] = []
        for (placement, run) in assigned {
            let date = calendar.date(for: placement.weekday, inWeekStarting: week.startDate)
            if let notBefore, date < calendar.startOfDay(for: notBefore) { continue }
            let type = run.session.runType
            let estimate = run.structure.estimate(zones: zones)
            var effort = run.session.isRace ? 9 : planRules.effort(type.rawValue)
            if type == .long && !run.session.isRace && estimate.durationSeconds > 90 * 60 { effort += 1 }
            let km = String(format: "%.1f", Units.distance(meters: estimate.distanceMeters, in: profile.units))
                + " " + Units.distanceUnitLabel(profile.units)
            generated.append(GeneratedSession(
                date: date, slot: placement.slot, kind: .run(type), isKey: false, title: run.session.name,
                summary: run.summary.isEmpty ? km : "\(run.summary) · \(km)",
                plannedDurationMinutes: max(5, (estimate.durationSeconds / 60 / 5).rounded() * 5), plannedEffort: effort,
                estimatedDistanceMeters: estimate.distanceMeters, runStructure: run.structure, strength: nil
            ))
        }
        var strengthWeek = week
        if strengthEmphasis == "light" { strengthWeek.isRecoveryWeek = true }
        let strengthContext = StrengthBuilder.Context(profile: profile, templates: templates, week: strengthWeek, workingWeights: workingWeights)
        for placement in liftPlacements {
            guard case .lift(let template) = placement.item else { continue }
            let date = calendar.date(for: placement.weekday, inWeekStarting: week.startDate)
            if let notBefore, date < calendar.startOfDay(for: notBefore) { continue }
            let prescription = StrengthBuilder.prescription(for: template, context: strengthContext)
            let totalSets = prescription.exercises.reduce(0) { $0 + $1.sets }
            var effort = planRules.effort("strength")
            if strengthWeek.isRecoveryWeek || week.phase == .taper { effort -= 1 }
            generated.append(GeneratedSession(
                date: date, slot: placement.slot, kind: .strength(template.focus), isKey: false, title: template.name,
                summary: "\(prescription.exercises.count) exercises · \(totalSets) sets",
                plannedDurationMinutes: StrengthBuilder.estimatedMinutes(prescription), plannedEffort: effort,
                estimatedDistanceMeters: nil, runStructure: nil, strength: prescription
            ))
        }
        generated.sort { $0.date == $1.date ? $0.slot.rawValue > $1.slot.rawValue : $0.date < $1.date }
        let plannedRunMeters = generated.compactMap(\.estimatedDistanceMeters).reduce(0, +)
        return GeneratedWeek(target: week, sessions: generated, plannedRunMeters: plannedRunMeters, notes: notes)
    }

    // MARK: Sizing the runs

    /// What sizing a week's runs needs.
    private struct WeekContext {
        var weekMeters: Double
        var shortest: Double
        var longestRun: Double
        var longShare: Double
        var longCap: Double
        var longSpec: ProgrammeDistance
        var raceMeters: Double
        var raceZone: PaceZone
        var raceLabel: String
        var programmeName: String
        var zones: PaceZones
        var rules: ProgrammeRules
    }

    /// Sizes and builds the week's runs:
    /// 1) the race and the long run;
    /// 2) rep sessions, with reps trimmed (further if the week is over) and a warm-up and cool-down;
    /// 3) everything else shares what's left, in the shape written, within sensible lengths.
    private static func allocate(_ sessions: [ProgrammeSession], context c: WeekContext) -> [PlannedRun] {
        var runs = sessions.map { PlannedRun(session: $0) }
        var longMeters = 0.0

        // 1) Race and long run.
        for i in runs.indices {
            let session = runs[i].session
            if session.isRace {
                runs[i].meters = c.raceMeters
                runs[i].structure = RunStructure(segments: [
                    RunSegment(kind: .work, length: .distance(meters: c.raceMeters), targetPace: c.zones.range(for: c.raceZone),
                               label: c.raceLabel == "race" ? "Race" : "Time trial")
                ])
                runs[i].summary = "\(c.programmeName) \(c.raceLabel)"
            } else if session.runType == .long {
                let spec = session.distance.kind == "auto" ? c.longSpec : session.distance
                var meters: Double
                switch spec.kind {
                case "meters": meters = spec.value ?? c.weekMeters * c.longShare
                case "share": meters = c.weekMeters * (spec.value ?? c.longShare)
                default: meters = c.weekMeters * c.longShare
                }
                meters = RunBuilder.tidy(min(max(meters, c.shortest), c.longCap))
                longMeters = meters
                runs[i].meters = meters
            }
        }

        func isFlexible(_ run: PlannedRun) -> Bool {
            !run.session.isRace && run.session.runType != .long && !run.session.isStructured
        }
        let flexibleAuto = runs.filter { isFlexible($0) && $0.session.distance.kind == "auto" }.count

        // 2) Rep sessions. If the long run and sessions leave too little for the other runs,
        //    warm-ups go down to the minimum and then the reps are trimmed further.
        let warmMin = c.rules.warmUpMin, warmUp = min(max(c.weekMeters * c.rules.warmUp, warmMin), max(c.rules.warmUpMax, warmMin))
        for (budget, warm) in [(1.0, warmUp), (1.0, warmMin), (0.8, warmMin), (0.65, warmMin), (0.5, warmMin)] {
            for i in runs.indices where runs[i].session.isStructured && !runs[i].session.isRace {
                let built = structured(runs[i].session, warmMeters: warm, weekMeters: c.weekMeters, budget: budget, rules: c.rules,
                                       zones: c.zones)
                runs[i].structure = built.structure
                runs[i].meters = built.structure.estimate(zones: c.zones).distanceMeters
                runs[i].summary = built.summary
            }
            let committed = runs.filter { !$0.session.isRace }.reduce(0) { $0 + $1.meters }
            if committed + c.shortest * Double(flexibleAuto) <= c.weekMeters * 1.05 { break }
        }

        // 3) Everything else shares what's left of the week.
        while true {
            let fixed = runs.filter { !isFlexible($0) && !$0.session.isRace }.reduce(0) { $0 + $1.meters }
            let explicitMeters = runs.filter { isFlexible($0) && $0.session.distance.kind != "auto" }
                .reduce(0) { $0 + explicitDistance($1.session.distance, weekMeters: c.weekMeters) }
            let autoRuns = runs.indices.filter { isFlexible(runs[$0]) && runs[$0].session.distance.kind == "auto" }
            let remaining = max(c.weekMeters - fixed - explicitMeters, 0)
            let totalWeight = autoRuns.reduce(0) { $0 + weight(runs[$1].session) }
            let perWeight = totalWeight > 0 ? remaining / totalWeight : 0
            // A run that would be too short is dropped (lowest priority first) and the rest re-shared.
            let tooShort = autoRuns.filter { weight(runs[$0].session) * perWeight < c.shortest }
            if !tooShort.isEmpty, let drop = tooShort.min(by: { dropPriority(runs[$0].session) ?? 9 < dropPriority(runs[$1].session) ?? 9 }) {
                runs.remove(at: drop)
                continue
            }
            for i in runs.indices where isFlexible(runs[i]) {
                let meters = runs[i].session.distance.kind == "auto"
                    ? weight(runs[i].session) * perWeight
                    : explicitDistance(runs[i].session.distance, weekMeters: c.weekMeters)
                let cap = maxLength(runs[i].session, longMeters: longMeters, context: c)
                runs[i].meters = RunBuilder.tidy(min(max(meters, c.shortest), max(cap, c.shortest)))
            }
            break
        }
        for i in runs.indices where runs[i].structure.segments.isEmpty {
            let built = flexible(runs[i].session, meters: runs[i].meters, zones: c.zones)
            runs[i].structure = built.structure
            runs[i].summary = built.summary
        }
        return runs
    }

    /// The longest an easier run should be: recovery runs well short of the long run, easy
    /// runs a little short of it, shakeouts short.
    private static func maxLength(_ session: ProgrammeSession, longMeters: Double, context c: WeekContext) -> Double {
        let long = longMeters > 0 ? longMeters : c.longestRun
        switch session.type {
        case "recovery": return min(long * c.rules.recoveryRunLimit, c.longestRun)
        case "easy": return session.name == "Shakeout" ? max(c.weekMeters * c.rules.shakeoutLimit, c.shortest)
            : min(long * c.rules.easyRunLimit, c.longestRun)
        default: return min(long, c.longestRun)
        }
    }

    // MARK: Fitting sessions to run days

    /// Which runs go first when there are fewer run days (nil = never dropped).
    static func dropPriority(_ session: ProgrammeSession) -> Int? {
        if session.isRace || session.runType == .long { return nil }
        if session.type == "recovery" { return 0 }
        if session.type == "easy" { return session.name == "Shakeout" ? 2 : 1 }
        return session.isStructured ? 4 : 3
    }

    static func fit(_ sessions: [ProgrammeSession], to count: Int) -> [ProgrammeSession] {
        var result = sessions
        while result.count > count {
            let candidates = result.indices.filter { dropPriority(result[$0]) != nil }
            // Lowest priority first; among equals, the later one.
            guard let drop = candidates.min(by: { a, b in
                let pa = dropPriority(result[a]) ?? 9, pb = dropPriority(result[b]) ?? 9
                return pa == pb ? a > b : pa < pb
            }) else { break }
            result.remove(at: drop)
        }
        while result.count < count {
            result.append(easySession(order: (result.map(\.order).max() ?? 0) + 1))
        }
        return result
    }

    static func easySession(order: Int) -> ProgrammeSession {
        ProgrammeSession(week: 0, order: order, name: "Easy run", type: "easy", distance: .auto,
                         parts: [WorkoutPart(kind: "share", share: 1, zone: "easy", repeats: nil, steps: nil, recovery: nil)],
                         text: nil, note: nil)
    }

    /// How big a share of the leftover volume a run gets.
    private static func weight(_ session: ProgrammeSession) -> Double {
        switch session.type {
        case "recovery": return 0.75
        case "easy": return session.name == "Shakeout" ? 0.6 : 1
        default: return 1.15 // progressions and other steady-but-harder runs
        }
    }

    private static func explicitDistance(_ distance: ProgrammeDistance, weekMeters: Double) -> Double {
        switch distance.kind {
        case "meters": return distance.value ?? 0
        case "share": return weekMeters * (distance.value ?? 0)
        default: return 0
        }
    }

    // MARK: Building runs

    /// Hard running allowed per session, by type of pace.
    private enum Intensity {
        case fast, threshold, sustained, easy

        init(zone: String) {
            switch zone {
            case "interval", "repetition", "fiveK", "hill": self = .fast
            case "threshold", "tenK": self = .threshold
            case "halfMarathon", "marathon", "steady": self = .sustained
            default: self = .easy
            }
        }

        func cap(weekMeters: Double, rules: ProgrammeRules) -> Double {
            switch self {
            case .fast: return max(weekMeters * (rules.fastRepsShare ?? 0.10), rules.fastRepsFloorMeters ?? 2000)
            case .threshold: return max(weekMeters * (rules.thresholdRepsShare ?? 0.15), rules.thresholdRepsFloorMeters ?? 3000)
            case .sustained: return max(weekMeters * (rules.steadyRepsShare ?? 0.25), rules.steadyRepsFloorMeters ?? 4000)
            case .easy: return .infinity
            }
        }
    }

    /// Reps for this runner: as written, or fewer so the hard running fits their week.
    static func repeats(for part: WorkoutPart, weekMeters: Double, budget: Double = 1, rules: ProgrammeRules = .fallback,
                        zones: PaceZones) -> Int {
        let written = max(part.repeats ?? 1, 1)
        guard written > 1 else { return written }
        var perRep: [Intensity: Double] = [:]
        for step in part.steps ?? [] where !step.isRecovery && step.label != "Stride" {
            perRep[Intensity(zone: step.zone), default: 0] += meters(of: step, zones: zones)
        }
        var allowed = written
        for (intensity, meters) in perRep where meters > 0 {
            allowed = min(allowed, Int((intensity.cap(weekMeters: weekMeters, rules: rules) * budget / meters).rounded(.down)))
        }
        return min(written, max(allowed, written >= 4 ? 2 : 1))
    }

    private static func pace(for zone: String, zones: PaceZones) -> Pace {
        switch zone {
        case "hill": return zones.typicalPace(for: .threshold)
        case "recovery": return Pace(secondsPerKm: zones.range(for: .easy).slowest.secondsPerKm + 15)
        default: return zones.typicalPace(for: PaceZone(rawValue: zone) ?? .easy)
        }
    }

    private static func meters(of step: WorkoutStepSpec, zones: PaceZones) -> Double {
        if let meters = step.meters { return meters }
        return (step.seconds ?? 60) / pace(for: step.zone, zones: zones).secondsPerKm * 1000
    }

    private static func range(for zone: String, zones: PaceZones) -> PaceRange? {
        switch zone {
        case "hill": return nil
        case "recovery":
            let easy = zones.range(for: .easy)
            return PaceRange(fastest: easy.slowest, slowest: Pace(secondsPerKm: easy.slowest.secondsPerKm + 30))
        default: return zones.range(for: PaceZone(rawValue: zone) ?? .easy)
        }
    }

    private static func zoneName(_ zone: String) -> String {
        switch zone {
        case "easy": return "Easy"
        case "recovery": return "Recovery"
        case "steady": return "Steady"
        case "marathon": return "Marathon pace"
        case "halfMarathon": return "Half-marathon pace"
        case "threshold": return "Threshold"
        case "tenK": return "10K pace"
        case "fiveK": return "5K pace"
        case "interval": return "Interval pace"
        case "repetition": return "Fast"
        case "hill": return "Uphill"
        default: return zone
        }
    }

    private static func zoneCode(_ zone: String) -> String {
        switch zone {
        case "easy", "recovery": return "E"
        case "steady": return "steady"
        case "marathon": return "M"
        case "halfMarathon": return "HM"
        case "threshold": return "T"
        case "tenK": return "10K"
        case "fiveK": return "5K"
        case "interval": return "I"
        case "repetition": return "R"
        case "hill": return "uphill"
        default: return zone
        }
    }

    private static func lengthText(_ step: WorkoutStepSpec) -> String {
        if let meters = step.meters {
            if meters >= 1000 {
                let km = meters / 1000
                return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
            }
            return "\(Int(meters)) m"
        }
        let seconds = Int(step.seconds ?? 60)
        return seconds % 60 == 0 && seconds >= 120 ? "\(seconds / 60) min" : (seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s")
    }

    private static func segment(_ step: WorkoutStepSpec, kind: SegmentKind, label: String, zones: PaceZones) -> RunSegment {
        let length: SegmentLength = step.meters.map { .distance(meters: $0) } ?? .duration(seconds: step.seconds ?? 60)
        let isGuide = step.effort == true && step.zone != "hill"
        return RunSegment(kind: kind, length: length, targetPace: range(for: step.zone, zones: zones), label: label,
                          paceIsGuide: isGuide ? true : nil)
    }

    /// The segments of a block of reps, and a short description ("6 × 800 m I").
    private static func expand(_ part: WorkoutPart, repeats: Int, zones: PaceZones) -> (segments: [RunSegment], summary: String) {
        let steps = part.steps ?? []
        let workSteps = steps.filter { !$0.isRecovery }
        let lastWork = steps.lastIndex { !$0.isRecovery } ?? 0
        var segments: [RunSegment] = []
        for rep in 0..<repeats {
            for (i, step) in steps.enumerated() {
                // The final rep ends on its last hard step (the cool-down follows).
                if rep == repeats - 1 && i > lastWork && step.isRecovery { continue }
                let label: String
                if step.isRecovery {
                    label = step.label ?? "Easy"
                } else if step.label == "Stride" {
                    label = "Stride \(rep + 1) of \(repeats)"
                } else if step.zone == "hill" {
                    label = "Hill \(rep + 1) of \(repeats) · hard effort"
                } else if repeats == 1 {
                    label = zoneName(step.zone)
                } else if workSteps.count > 1 {
                    label = "Rep \(rep + 1) of \(repeats) · \(zoneName(step.zone))"
                } else {
                    label = "Rep \(rep + 1) of \(repeats)"
                }
                segments.append(segment(step, kind: step.isRecovery ? .recovery : .work, label: label, zones: zones))
            }
            if let recovery = part.recovery, rep < repeats - 1 {
                segments.append(segment(recovery, kind: .recovery, label: recovery.label ?? "Recovery jog", zones: zones))
            }
        }
        let summary: String
        if workSteps.first?.label == "Stride" {
            summary = "\(repeats) strides"
        } else if workSteps.count == 1, let step = workSteps.first {
            let zone = step.zone == "hill" ? "hills" : zoneCode(step.zone)
            summary = repeats == 1 ? "\(lengthText(step)) \(zone)" : "\(repeats) × \(lengthText(step)) \(zone)"
        } else {
            let lengths = steps.map(lengthText).joined(separator: " / ")
            summary = "\(repeats) × (\(lengths))"
        }
        return (segments, summary)
    }

    /// A rep or tempo session with an easy warm-up and cool-down.
    private static func structured(_ session: ProgrammeSession, warmMeters: Double, weekMeters: Double, budget: Double,
                                   rules: ProgrammeRules,
                                   zones: PaceZones) -> (structure: RunStructure, summary: String) {
        let easy = zones.range(for: .easy)
        var segments = [RunSegment(kind: .warmUp, length: .distance(meters: RunBuilder.tidy(warmMeters)), targetPace: easy, label: "Warm-up")]
        var summaries: [String] = []
        for part in session.parts where part.kind == "reps" {
            let count = repeats(for: part, weekMeters: weekMeters, budget: budget, rules: rules, zones: zones)
            let block = expand(part, repeats: count, zones: zones)
            segments += block.segments
            summaries.append(block.summary)
        }
        segments.append(RunSegment(kind: .coolDown, length: .distance(meters: RunBuilder.tidy(warmMeters)), targetPace: easy, label: "Cool-down"))
        return (RunStructure(segments: segments), summaries.joined(separator: " + "))
    }

    /// An easy, recovery, long or progression run of a given distance, in the shape written.
    private static func flexible(_ session: ProgrammeSession, meters total: Double,
                                 zones: PaceZones) -> (structure: RunStructure, summary: String) {
        let shares = session.parts.filter { $0.kind == "share" }
        let blocks = session.parts.filter { $0.kind == "reps" }
        // A plain run: one steady segment, as for the rule-based plans.
        if shares.count <= 1 && blocks.isEmpty {
            let zone = shares.first?.zone ?? "easy"
            let type: RunSessionType = zone == "recovery" ? .recovery : session.runType
            return (RunBuilder.steady(type == .tempo || type == .intervals ? .easy : type, distanceMeters: total, zones: zones), "")
        }
        var segments: [RunSegment] = []
        var summaries: [String] = []
        let totalShare = shares.reduce(0) { $0 + ($1.share ?? 0) }
        for part in shares {
            let zone = part.zone ?? "easy"
            let meters = RunBuilder.tidy(total * (part.share ?? 0) / max(totalShare, 0.0001))
            guard meters > 0 else { continue }
            segments.append(RunSegment(kind: .steady, length: .distance(meters: meters), targetPace: range(for: zone, zones: zones),
                                       label: zoneName(zone)))
        }
        if shares.count > 1 {
            summaries.append(shares.compactMap { $0.zone.map(zoneCode) }.joined(separator: " → "))
        }
        for part in blocks {
            let block = expand(part, repeats: max(part.repeats ?? 1, 1), zones: zones)
            segments += block.segments
            summaries.append(block.summary)
        }
        return (RunStructure(segments: segments), summaries.joined(separator: " + "))
    }
}
