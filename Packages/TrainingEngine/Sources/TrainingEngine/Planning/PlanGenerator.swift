import Foundation

/// A session ready to be stored in the user's plan.
public struct GeneratedSession: Codable, Equatable, Sendable {
    public var date: Date
    public var slot: SessionSlot
    public var kind: SessionKind
    /// Key sessions are protected when the week is rebalanced.
    public var isKey: Bool
    public var title: String
    /// Short description, e.g. "6 × 800 m · 9.5 km".
    public var summary: String
    public var plannedDurationMinutes: Double
    /// Expected effort 1-10 (for planned load).
    public var plannedEffort: Double
    public var estimatedDistanceMeters: Double?
    public var runStructure: RunStructure?
    public var strength: StrengthPrescription?
}

public struct GeneratedWeek: Equatable, Sendable {
    public var target: WeekTarget
    public var sessions: [GeneratedSession]
    /// Planned running distance from the generated sessions.
    public var plannedRunMeters: Double
    /// One-sentence explanations of scheduling decisions.
    public var notes: [String]
}

/// Turns an athlete profile into a periodised, interference-aware hybrid plan.
public struct PlanGenerator: Sendable {
    public let templates: TemplateLibrary
    public let calendar: Calendar

    public init(templates: TemplateLibrary, calendar: Calendar = .kinetix) {
        self.templates = templates
        self.calendar = calendar
    }

    /// The Monday the plan starts: this week if it's Monday–Wednesday, else next week.
    public func planStart(from today: Date) -> Date {
        let monday = calendar.startOfISOWeek(for: today)
        if calendar.weekday(of: today).rawValue <= Weekday.wednesday.rawValue { return monday }
        return calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
    }

    public func weeklyMixCounts(for profile: AthleteProfile) -> (runs: Int, lifts: Int) {
        let counts = MixBuilder.sessionCounts(profile: profile, rules: templates.rules)
        return (counts.runs, counts.lifts)
    }

    public func makeOutline(for profile: AthleteProfile, startingOn monday: Date) -> PlanOutline {
        let counts = MixBuilder.sessionCounts(profile: profile, rules: templates.rules)
        return OutlineBuilder.build(
            profile: profile,
            startMonday: calendar.startOfISOWeek(for: monday),
            runsPerWeek: counts.runs,
            rules: templates.rules,
            calendar: calendar
        )
    }

    /// Generates the detailed sessions for one week of the outline.
    /// - Parameters:
    ///   - workingWeights: current working weights by `ExercisePrescription.progressionKey`.
    ///   - notBefore: sessions on earlier dates are omitted (e.g. days already past).
    public func generateWeek(
        _ index: Int,
        outline: PlanOutline,
        profile: AthleteProfile,
        workingWeights: [String: Double] = [:],
        notBefore: Date? = nil
    ) -> GeneratedWeek? {
        guard outline.weeks.indices.contains(index) else { return nil }
        let week = outline.weeks[index]
        let zones = PaceZones(profile: profile)
        let mix = MixBuilder.build(profile: profile, week: week, templates: templates)
        let schedule = WeekScheduler.schedule(
            days: mix.trainingDays,
            doubleDays: mix.doubleDays,
            runs: mix.runs,
            lifts: mix.lifts,
            prioritiseLifts: profile.goal == .buildStrength || profile.goal == .buildMuscle
        )
        let rules = templates.rules
        let goalRules = rules.goal(profile.goal)
        let level = profile.runningExperience

        // Build quality runs first so their distance is known before sharing out the rest.
        var qualityStructures: [Weekday: (RunWorkoutTemplate, RunStructure)] = [:]
        for placement in schedule.placements {
            guard case .run(let type) = placement.item, type == .tempo || type == .intervals else { continue }
            let options = templates.workouts(type: type, level: level)
            guard !options.isEmpty else { continue }
            let step = (week.isRecoveryWeek || week.phase == .taper) ? 0 : min(week.weekInPhase, options.count - 1)
            let template = options[step]
            qualityStructures[placement.weekday] = (template, RunBuilder.structure(from: template, zones: zones))
        }
        let qualityMeters = qualityStructures.values.reduce(0) { $0 + $1.1.estimate(zones: zones).distanceMeters }

        let maxRun = rules.maxRunMeters[level.rawValue] ?? 12000
        let target = week.runVolumeMeters
        let hasLong = schedule.placements.contains { $0.item == .run(.long) }
        let easyCount = schedule.placements.filter { $0.item == .run(.easy) }.count
        let longMeters: Double = hasLong
            ? RunBuilder.tidy(min(max(target * goalRules.longRunShare, rules.minRunMeters), goalRules.longRunCapMeters, maxRun * 1.8))
            : 0
        let remainder = target - longMeters - qualityMeters
        let easyMeters = easyCount > 0
            ? RunBuilder.tidy(min(max(remainder / Double(easyCount), rules.minRunMeters), maxRun))
            : 0

        let strengthContext = StrengthBuilder.Context(profile: profile, templates: templates, week: week, workingWeights: workingWeights)
        let liftsAreKey = !profile.goal.isRunningFocused
        let runsAreKey = profile.goal != .buildStrength && profile.goal != .buildMuscle

        var sessions: [GeneratedSession] = []
        for placement in schedule.placements {
            let date = calendar.date(for: placement.weekday, inWeekStarting: week.startDate)
            if let notBefore, date < calendar.startOfDay(for: notBefore) { continue }

            switch placement.item {
            case .run(let type):
                let structure: RunStructure
                var summaryPrefix = ""
                if let quality = qualityStructures[placement.weekday] {
                    structure = quality.1
                    summaryPrefix = quality.0.name + " · "
                } else {
                    structure = RunBuilder.steady(type, distanceMeters: type == .long ? longMeters : easyMeters, zones: zones)
                }
                let estimate = structure.estimate(zones: zones)
                var effort = rules.effort(type.rawValue)
                if type == .long && estimate.durationSeconds > 90 * 60 { effort += 1 }
                sessions.append(GeneratedSession(
                    date: date,
                    slot: placement.slot,
                    kind: .run(type),
                    isKey: runsAreKey && type.isQuality,
                    title: SessionKind.run(type).displayName,
                    summary: summaryPrefix
                        + String(format: "%.1f", Units.distance(meters: estimate.distanceMeters, in: profile.units))
                        + " " + Units.distanceUnitLabel(profile.units),
                    plannedDurationMinutes: max(5, (estimate.durationSeconds / 60 / 5).rounded() * 5),
                    plannedEffort: effort,
                    estimatedDistanceMeters: estimate.distanceMeters,
                    runStructure: structure,
                    strength: nil
                ))

            case .lift(let template):
                let prescription = StrengthBuilder.prescription(for: template, context: strengthContext)
                let totalSets = prescription.exercises.reduce(0) { $0 + $1.sets }
                var effort = rules.effort("strength")
                if week.isRecoveryWeek || week.phase == .taper { effort -= 1 }
                sessions.append(GeneratedSession(
                    date: date,
                    slot: placement.slot,
                    kind: .strength(template.focus),
                    isKey: liftsAreKey,
                    title: template.name,
                    summary: "\(prescription.exercises.count) exercises · \(totalSets) sets",
                    plannedDurationMinutes: StrengthBuilder.estimatedMinutes(prescription),
                    plannedEffort: effort,
                    estimatedDistanceMeters: nil,
                    runStructure: nil,
                    strength: prescription
                ))
            }
        }

        let plannedRunMeters = sessions.compactMap(\.estimatedDistanceMeters).reduce(0, +)
        var notes = mix.notes + schedule.notes
        if week.isRecoveryWeek { notes.append("Recovery week: volume is down about 20% so your body can absorb the last few weeks.") }
        if week.phase == .taper && index == outline.weeks.count - 1 && outline.eventDate != nil {
            notes.append("Race week: sessions are short and sharp so you arrive fresh.")
        }
        return GeneratedWeek(target: week, sessions: sessions, plannedRunMeters: plannedRunMeters, notes: notes)
    }
}

extension Calendar {
    /// Gregorian calendar with Monday as the first weekday, in the current time zone.
    public static var kinetix: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }
}
