import Foundation
import Observation
import TrainingEngine

/// Answers collected during onboarding and the step navigation.
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case units, age, runningExperience, raceTime, currentRunning, liftingExperience, liftEstimates,
             goal, eventDate, gymWeek, trainingDays, doubleSessions, equipment, finish
    }

    enum RaceDistance: Double, CaseIterable, Identifiable {
        case fiveK = 5000, tenK = 10000, half = 21097.5, marathon = 42195
        var id: Double { rawValue }
        var label: String {
            switch self {
            case .fiveK: return "5K"
            case .tenK: return "10K"
            case .half: return "Half"
            case .marathon: return "Marathon"
            }
        }
    }

    struct LiftEntry: Identifiable {
        let lift: MainLift
        var isKnown = false
        /// Always stored in kg; displayed in the chosen units.
        var weightKg: Double
        var reps: Double = 5
        var id: MainLift { lift }
    }

    var step: Step = .units

    var units: UnitSystem = UnitPreference.stored
    /// Age sets max heart rate and so the heart-rate zones (skipped = not known).
    var knowsAge = true
    var age = 30
    /// Kept as they were when editing (set in Settings → Heart rate zones).
    private var heartRateZones: HeartRateZoneSettings?
    /// Kept as they were when editing (set from the gym screen, not asked here).
    private var exerciseSwaps: [String: String]?
    /// The day they want the plan to start (nil = as soon as sensible). Set on the plan preview.
    var planStartDate: Date?
    var runningExperience: ExperienceLevel?
    var knowsRaceTime = false
    var raceDistance: RaceDistance = .fiveK
    var raceHours = 0
    var raceMinutes = 25
    var raceSeconds = 0
    /// "How much do you run now?" (skipped = not known).
    var knowsCurrentRunning = true
    var weeklyRunMeters: Double = 20000
    var longestRunMeters: Double = 8000
    /// Their last four weeks from Kinetix, Strava and Apple Health, if the app has any.
    var recentHistory: RecentRunning.Summary?
    /// New plans use the history straight away; editing in Settings offers it instead.
    var applyHistoryAutomatically = true
    /// "Have you raced in the last two weeks?" and "Start with an easy week?"
    var racedRecently = false
    var easyFirstWeek = true
    private var easyFirstWeekRequestedAt: Date?
    var liftingExperience: ExperienceLevel?
    var liftEntries: [LiftEntry] = [
        LiftEntry(lift: .squat, weightKg: 60),
        LiftEntry(lift: .benchPress, weightKg: 50),
        LiftEntry(lift: .deadlift, weightKg: 80),
        LiftEntry(lift: .overheadPress, weightKg: 30)
    ]
    var goal: TrainingGoal?
    /// Hyrox race category, asked when the goal is Hyrox.
    var hyroxDivision: HyroxDivision?
    var hasEvent = false
    var eventDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now
    var trainingDays: Set<Weekday> = [.monday, .tuesday, .thursday, .saturday]
    /// Gym sessions a week and the split (set on the gym week screen; until then the plan
    /// decides, as for profiles made before the question existed).
    var liftSessionsPerWeek = 2
    var splitCode: String?
    var gymWeekChosen = false
    var doubleSessionDays = 0
    var equipment: Equipment?
    /// The health & safety notice must be acknowledged before a plan is built.
    var acceptedHealthNotice = false

    var totalSteps: Int { Step.allCases.count }
    var stepNumber: Int { step.rawValue + 1 }

    var canContinue: Bool {
        switch step {
        case .units: return true
        case .age: return !knowsAge || (13...100).contains(age)
        case .runningExperience: return runningExperience != nil
        case .raceTime: return !knowsRaceTime || raceTimeSeconds >= 600
        case .currentRunning: return true
        case .liftingExperience: return liftingExperience != nil
        case .liftEstimates: return true
        case .goal: return goal != nil && (goal != .hyrox || hyroxDivision != nil)
        case .eventDate: return !hasEvent || eventDate > .now
        case .gymWeek: return liftSessionsPerWeek == 0 || splitCode != nil
        case .trainingDays: return (2...7).contains(trainingDays.count)
        case .doubleSessions: return true
        case .equipment: return equipment != nil
        case .finish: return acceptedHealthNotice
        }
    }

    /// Steps that can be skipped with a "Skip" button.
    var isOptional: Bool {
        [.age, .raceTime, .currentRunning, .liftEstimates, .eventDate].contains(step)
    }

    var raceTimeSeconds: Double {
        Double(raceHours * 3600 + raceMinutes * 60 + raceSeconds)
    }

    var maxDoubleDays: Int { min(3, trainingDays.count) }

    func next() {
        if step == .trainingDays { doubleSessionDays = min(doubleSessionDays, maxDoubleDays) }
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func skip() {
        clear(step)
        next()
    }

    /// Clears an optional answer (Skip in onboarding, "Clear answer" when editing).
    func clear(_ step: Step) {
        switch step {
        case .age: knowsAge = false
        case .raceTime: knowsRaceTime = false
        case .currentRunning: knowsCurrentRunning = false
        case .liftEstimates:
            for index in liftEntries.indices { liftEntries[index].isKnown = false }
        case .eventDate: hasEvent = false
        default: break
        }
    }

    /// The engine profile built from the answers.
    var profile: AthleteProfile {
        AthleteProfile(
            runningExperience: runningExperience ?? .beginner,
            recentRace: knowsRaceTime ? RaceResult(distanceMeters: raceDistance.rawValue, timeSeconds: raceTimeSeconds) : nil,
            liftingExperience: liftingExperience ?? .beginner,
            liftEstimates: liftEntries.filter(\.isKnown).map {
                LiftEstimate(lift: $0.lift, weightKg: $0.weightKg, reps: Int($0.reps))
            },
            goal: goal ?? .balancedHybrid,
            eventDate: hasEvent ? eventDate : nil,
            trainingDays: Array(trainingDays),
            doubleSessionDays: doubleSessionDays,
            equipment: equipment ?? .fullGym,
            units: units,
            weeklyRunMeters: knowsCurrentRunning ? weeklyRunMeters : nil,
            longestRecentRunMeters: knowsCurrentRunning && weeklyRunMeters > 0 ? longestRunMeters : nil,
            racedRecently: racedRecently ? true : nil,
            easyFirstWeek: racedRecently ? easyFirstWeek : nil,
            easyFirstWeekRequestedAt: racedRecently && easyFirstWeek ? (easyFirstWeekRequestedAt ?? Date()) : nil,
            liftSessionsPerWeek: gymWeekChosen ? liftSessionsPerWeek : nil,
            splitCode: gymWeekChosen && liftSessionsPerWeek > 0 ? splitCode : nil,
            birthYear: knowsAge ? Calendar.current.component(.year, from: .now) - age : nil,
            heartRateZones: heartRateZones,
            hyroxDivision: goal == .hyrox ? hyroxDivision : nil,
            exerciseSwaps: exerciseSwaps,
            planStartDate: planStartDate
        )
    }

    /// Fills in the running answers from their history.
    func useHistory() {
        guard let recentHistory else { return }
        knowsCurrentRunning = true
        weeklyRunMeters = (recentHistory.weeklyMeters / 1000).rounded() * 1000
        longestRunMeters = max((recentHistory.longestMeters / 1000).rounded() * 1000, 1000)
    }

    /// Loads existing answers (used when editing the training profile in Settings).
    func load(_ profile: AthleteProfile) {
        acceptedHealthNotice = true
        units = profile.units
        runningExperience = profile.runningExperience
        knowsAge = profile.birthYear != nil
        if let profileAge = profile.age() { age = profileAge }
        heartRateZones = profile.heartRateZones
        exerciseSwaps = profile.exerciseSwaps
        planStartDate = profile.planStartDate
        if let race = profile.recentRace {
            knowsRaceTime = true
            raceDistance = RaceDistance.allCases.min { abs($0.rawValue - race.distanceMeters) < abs($1.rawValue - race.distanceMeters) } ?? .fiveK
            let total = Int(race.timeSeconds.rounded())
            raceHours = total / 3600
            raceMinutes = (total % 3600) / 60
            raceSeconds = total % 60
        } else {
            knowsRaceTime = false
        }
        applyHistoryAutomatically = false
        gymWeekChosen = profile.liftSessionsPerWeek != nil
        if let lifts = profile.liftSessionsPerWeek { liftSessionsPerWeek = lifts }
        splitCode = profile.splitCode
        racedRecently = profile.racedRecently ?? false
        easyFirstWeek = profile.easyFirstWeek ?? true
        easyFirstWeekRequestedAt = profile.easyFirstWeekRequestedAt
        knowsCurrentRunning = profile.weeklyRunMeters != nil
        if let weekly = profile.weeklyRunMeters { weeklyRunMeters = weekly }
        if let longest = profile.longestRecentRunMeters { longestRunMeters = longest }
        liftingExperience = profile.liftingExperience
        for index in liftEntries.indices {
            if let estimate = profile.liftEstimates.first(where: { $0.lift == liftEntries[index].lift }) {
                liftEntries[index].isKnown = true
                liftEntries[index].weightKg = estimate.weightKg
                liftEntries[index].reps = Double(estimate.reps)
            } else {
                liftEntries[index].isKnown = false
            }
        }
        goal = profile.goal
        hyroxDivision = profile.hyroxDivision
        hasEvent = profile.eventDate != nil
        if let event = profile.eventDate { eventDate = event }
        trainingDays = Set(profile.trainingDays)
        doubleSessionDays = profile.doubleSessionDays
        equipment = profile.equipment
    }

    #if DEBUG
    /// Fills in typical answers (development shortcut).
    func fillSampleAnswers() {
        units = .metric
        runningExperience = .intermediate
        knowsRaceTime = true
        raceDistance = .fiveK
        raceMinutes = 23
        liftingExperience = .intermediate
        goal = .halfMarathon
        hasEvent = true
        trainingDays = [.monday, .tuesday, .wednesday, .friday, .saturday, .sunday]
        doubleSessionDays = 1
        equipment = .fullGym
        step = .finish
    }
    #endif
}

extension MainLift {
    var displayName: String {
        switch self {
        case .squat: return "Back squat"
        case .deadlift: return "Deadlift"
        case .benchPress: return "Bench press"
        case .overheadPress: return "Overhead press"
        case .row: return "Barbell row"
        }
    }
}

extension ExperienceLevel {
    var displayName: String { rawValue.capitalized }
}
