import Foundation

/// A plan the athlete builds themselves: one typical week, repeated and built up week by
/// week, with easier weeks and a taper before a race.
public struct CustomPlan: Codable, Equatable, Sendable {
    public enum Activity: Codable, Equatable, Sendable {
        /// A Kinetix run type at a starting distance (easy, long and recovery runs grow;
        /// tempo and intervals follow Kinetix's sessions for the week).
        case run(RunSessionType, meters: Double)
        /// One of their saved run workouts, as it is.
        case runWorkout(CustomRunWorkout)
        /// A Kinetix gym session from the template library (e.g. "upperA").
        case gymSession(String)
        /// One of their saved gym workouts.
        case gymWorkout(name: String, exercises: [GymTemplateItem])
        /// Easy cycling, cross-trainer or a brisk walk.
        case crossTraining(minutes: Double)

        public var discipline: Discipline {
            switch self {
            case .run, .runWorkout: return .run
            case .gymSession, .gymWorkout: return .strength
            case .crossTraining: return .crossTraining
            }
        }
    }

    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var weekday: Weekday
        public var slot: SessionSlot
        public var activity: Activity

        public init(id: UUID = UUID(), weekday: Weekday, slot: SessionSlot = .morning, activity: Activity) {
            self.id = id
            self.weekday = weekday
            self.slot = slot
            self.activity = activity
        }
    }

    public var name: String
    public var weeks: Int
    /// Monday of week 1.
    public var startDate: Date
    public var raceMeters: Double?
    public var raceDate: Date?
    public var items: [Item]
    /// Weekly growth of the long run and of other runs (0.08 = 8%), capped at 10%.
    public var longRunGrowth: Double
    public var runGrowth: Double
    /// An easier week every N weeks (0 = never), at this share of the week before.
    public var deloadEvery: Int
    public var deloadShare: Double

    public init(name: String, weeks: Int, startDate: Date, raceMeters: Double? = nil, raceDate: Date? = nil, items: [Item] = [],
                longRunGrowth: Double = 0.08, runGrowth: Double = 0.05, deloadEvery: Int = 4, deloadShare: Double = 0.7) {
        self.name = name
        self.weeks = weeks
        self.startDate = startDate
        self.raceMeters = raceMeters
        self.raceDate = raceDate
        self.items = items
        self.longRunGrowth = longRunGrowth
        self.runGrowth = runGrowth
        self.deloadEvery = deloadEvery
        self.deloadShare = deloadShare
    }

    public var hasRace: Bool { raceMeters != nil && raceDate != nil }
    static let taperShares = [0.75, 0.5]

    public enum WeekKind: Equatable, Sendable { case build, easier, taper }

    /// What each week is: building, an easier week, or the taper before the race.
    public var weekKinds: [WeekKind] {
        (0..<weeks).map { index in
            let taperStart = hasRace ? weeks - Self.taperShares.count : weeks
            if index >= taperStart { return .taper }
            if deloadEvery > 1, (index + 1) % deloadEvery == 0 { return .easier }
            return .build
        }
    }

    /// How much of week 1's distance each week holds, for long runs (`long`) or other runs.
    public func volumeFactors(long: Bool) -> [Double] {
        let growth = min(max(long ? longRunGrowth : runGrowth, 0), 0.10)
        var build = 1.0
        var factors: [Double] = []
        let kinds = weekKinds
        var taperIndex = 0
        for (index, kind) in kinds.enumerated() {
            switch kind {
            case .build:
                if index > 0, kinds[index - 1] == .build { build *= 1 + growth }
                factors.append(build)
            case .easier:
                factors.append(build * deloadShare)
            case .taper:
                factors.append(build * Self.taperShares[min(taperIndex, Self.taperShares.count - 1)])
                taperIndex += 1
            }
        }
        return factors
    }
}

/// Turns a custom plan into an outline and weekly sessions, like the coach's programmes.
enum CustomPlanGenerator {
    static func outline(_ plan: CustomPlan, calendar: Calendar) -> PlanOutline {
        let monday = calendar.startOfISOWeek(for: plan.startDate)
        let longFactors = plan.volumeFactors(long: true)
        let otherFactors = plan.volumeFactors(long: false)
        let kinds = plan.weekKinds
        let longBase = plan.items.reduce(0.0) { total, item in
            if case .run(.long, let meters) = item.activity { return total + meters }
            return total
        }
        let otherBase = plan.items.reduce(0.0) { total, item in
            if case .run(let type, let meters) = item.activity, type != .long { return total + meters }
            return total
        }
        var weeks: [WeekTarget] = []
        var weekInPhase = 0
        var lastPhase: TrainingPhase?
        for index in 0..<plan.weeks {
            let start = calendar.date(byAdding: .day, value: 7 * index, to: monday) ?? monday
            let phase: TrainingPhase = kinds[index] == .taper ? .taper : index < plan.weeks / 3 ? .base : .build
            weekInPhase = phase == lastPhase ? weekInPhase + 1 : 0
            lastPhase = phase
            weeks.append(WeekTarget(index: index, startDate: start, phase: phase, weekInPhase: weekInPhase,
                                    isRecoveryWeek: kinds[index] == .easier,
                                    runVolumeMeters: longBase * longFactors[index] + otherBase * otherFactors[index]))
        }
        var outline = PlanOutline(startDate: monday, eventDate: plan.raceDate, weeks: weeks)
        outline.customPlan = plan
        return outline
    }

    static func generateWeek(_ index: Int, plan: CustomPlan, outline: PlanOutline, profile: AthleteProfile, templates: TemplateLibrary,
                             workingWeights: [String: Double], notBefore: Date?, calendar: Calendar) -> GeneratedWeek? {
        guard outline.weeks.indices.contains(index) else { return nil }
        let week = outline.weeks[index]
        let zones = PaceZones(profile: profile)
        let rules = templates.rules
        let longFactor = plan.volumeFactors(long: true)[index]
        let otherFactor = plan.volumeFactors(long: false)[index]
        let lighter = week.isRecoveryWeek || week.phase == .taper
        let strengthContext = StrengthBuilder.Context(profile: profile, templates: templates, week: week, workingWeights: workingWeights)
        var sessions: [GeneratedSession] = []

        func runSession(date: Date, slot: SessionSlot, type: RunSessionType, title: String? = nil, structure: RunStructure,
                        prefix: String = "") -> GeneratedSession {
            let estimate = structure.estimate(zones: zones)
            var effort = rules.effort(type.rawValue)
            if type == .long && estimate.durationSeconds > 90 * 60 { effort += 1 }
            return GeneratedSession(
                date: date, slot: slot, kind: .run(type), isKey: false, title: title ?? SessionKind.run(type).displayName,
                summary: prefix + String(format: "%.1f", Units.distance(meters: estimate.distanceMeters, in: profile.units))
                    + " " + Units.distanceUnitLabel(profile.units),
                plannedDurationMinutes: max(5, (estimate.durationSeconds / 60 / 5).rounded() * 5),
                plannedEffort: effort, estimatedDistanceMeters: estimate.distanceMeters, runStructure: structure, strength: nil)
        }

        for item in plan.items {
            let date = calendar.date(for: item.weekday, inWeekStarting: week.startDate)
            if let notBefore, date < calendar.startOfDay(for: notBefore) { continue }
            // Race day: the race takes the place of whatever was planned.
            if let raceDate = plan.raceDate, calendar.isDate(raceDate, inSameDayAs: date) { continue }
            switch item.activity {
            case .run(let type, let meters):
                if type == .tempo || type == .intervals {
                    let options = templates.workouts(type: type, level: profile.runningExperience)
                    if !options.isEmpty {
                        let template = options[lighter ? 0 : min(week.weekInPhase, options.count - 1)]
                        sessions.append(runSession(date: date, slot: item.slot, type: type,
                                                   structure: RunBuilder.structure(from: template, zones: zones), prefix: template.name + " · "))
                        continue
                    }
                }
                let factor = type == .long ? longFactor : otherFactor
                let distance = RunBuilder.tidy(max(meters * factor, rules.minRunMeters))
                sessions.append(runSession(date: date, slot: item.slot, type: type,
                                           structure: RunBuilder.steady(type, distanceMeters: distance, zones: zones)))
            case .runWorkout(let workout):
                guard let structure = workout.structure else { continue }
                let type = workout.type.sessionType ?? .tempo
                sessions.append(runSession(date: date, slot: item.slot, type: type, title: workout.name, structure: structure))
            case .gymSession(let key):
                guard let template = templates.strength.sessions[key] else { continue }
                let prescription = StrengthBuilder.prescription(for: template, context: strengthContext)
                sessions.append(gymSession(date: date, slot: item.slot, focus: template.focus, title: template.name,
                                           prescription: prescription, lighter: lighter, rules: rules))
            case .gymWorkout(let name, let exercises):
                let prescription = StrengthPrescription(exercises: exercises.map { item in
                    let key = "\(item.exerciseId).main"
                    let weight = item.isBodyweight ? nil : (workingWeights[key] ?? workingWeights["\(item.exerciseId).accessory"] ?? 0)
                    return ExercisePrescription(exerciseId: item.exerciseId, name: item.name, role: .main,
                                                sets: lighter ? max(1, item.sets - 1) : item.sets,
                                                repRange: RepRange(item.repsLow, item.repsHigh), weightKg: weight,
                                                restSeconds: item.restSeconds)
                })
                sessions.append(gymSession(date: date, slot: item.slot, focus: focus(named: name), title: name,
                                           prescription: prescription, lighter: lighter, rules: rules))
            case .crossTraining(let minutes):
                sessions.append(GeneratedSession(
                    date: date, slot: item.slot, kind: .crossTraining, isKey: false, title: SessionKind.crossTraining.displayName,
                    summary: "\(Int(minutes)) min easy cycling, cross-trainer or brisk walk", plannedDurationMinutes: minutes,
                    plannedEffort: rules.effort("crossTraining"), estimatedDistanceMeters: nil, runStructure: nil, strength: nil))
            }
        }

        // The race itself.
        if let raceMeters = plan.raceMeters, let raceDate = plan.raceDate,
           raceDate >= week.startDate, raceDate < (calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? raceDate),
           notBefore.map({ raceDate >= calendar.startOfDay(for: $0) }) ?? true,
           let structure = CustomRunWorkout.race(meters: raceMeters, zones: zones).structure {
            var race = runSession(date: calendar.startOfDay(for: raceDate), slot: .morning, type: .tempo, title: "Race day", structure: structure)
            race.plannedEffort = 9
            sessions.append(race)
        }

        sessions.sort { ($0.date, $0.slot == .morning ? 0 : 1) < ($1.date, $1.slot == .morning ? 0 : 1) }
        let runMeters = sessions.compactMap(\.estimatedDistanceMeters).reduce(0, +)
        var notes: [String] = []
        if week.isRecoveryWeek { notes.append("An easier week: runs are shorter so the last few weeks sink in.") }
        if week.phase == .taper { notes.append("Taper: less running so you start the race fresh.") }
        return GeneratedWeek(target: week, sessions: sessions, plannedRunMeters: runMeters, notes: notes)
    }

    /// A saved gym workout's focus from its name ("Legs", "Push day"…), for scheduling rules.
    static func focus(named name: String) -> StrengthFocus {
        let lower = name.lowercased()
        if lower.contains("leg") || lower.contains("lower") { return .legs }
        if lower.contains("push") { return .push }
        if lower.contains("pull") { return .pull }
        if lower.contains("upper") { return .upper }
        return .fullBody
    }

    private static func gymSession(date: Date, slot: SessionSlot, focus: StrengthFocus, title: String,
                                   prescription: StrengthPrescription, lighter: Bool, rules: PlanRules) -> GeneratedSession {
        let sets = prescription.exercises.reduce(0) { $0 + $1.sets }
        var effort = rules.effort("strength")
        if lighter { effort -= 1 }
        return GeneratedSession(
            date: date, slot: slot, kind: .strength(focus), isKey: false, title: title,
            summary: "\(prescription.exercises.count) exercises · \(sets) sets",
            plannedDurationMinutes: max(20, Double(sets) * 3), plannedEffort: effort,
            estimatedDistanceMeters: nil, runStructure: nil, strength: prescription)
    }
}
