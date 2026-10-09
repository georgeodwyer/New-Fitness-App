import Foundation
import Observation
import TrainingEngine

/// Answers collected during onboarding and the step navigation.
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case units, runningExperience, raceTime, liftingExperience, liftEstimates,
             goal, eventDate, trainingDays, doubleSessions, equipment, finish
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

    var units: UnitSystem = .metric
    var runningExperience: ExperienceLevel?
    var knowsRaceTime = false
    var raceDistance: RaceDistance = .fiveK
    var raceHours = 0
    var raceMinutes = 25
    var raceSeconds = 0
    var liftingExperience: ExperienceLevel?
    var liftEntries: [LiftEntry] = [
        LiftEntry(lift: .squat, weightKg: 60),
        LiftEntry(lift: .benchPress, weightKg: 50),
        LiftEntry(lift: .deadlift, weightKg: 80),
        LiftEntry(lift: .overheadPress, weightKg: 30)
    ]
    var goal: TrainingGoal?
    var hasEvent = false
    var eventDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now
    var trainingDays: Set<Weekday> = [.monday, .tuesday, .thursday, .saturday]
    var doubleSessionDays = 0
    var equipment: Equipment?

    var totalSteps: Int { Step.allCases.count }
    var stepNumber: Int { step.rawValue + 1 }

    var canContinue: Bool {
        switch step {
        case .units: return true
        case .runningExperience: return runningExperience != nil
        case .raceTime: return !knowsRaceTime || raceTimeSeconds >= 600
        case .liftingExperience: return liftingExperience != nil
        case .liftEstimates: return true
        case .goal: return goal != nil
        case .eventDate: return !hasEvent || eventDate > .now
        case .trainingDays: return (2...7).contains(trainingDays.count)
        case .doubleSessions: return true
        case .equipment: return equipment != nil
        case .finish: return true
        }
    }

    /// Steps that can be skipped with a "Skip" button.
    var isOptional: Bool {
        [.raceTime, .liftEstimates, .eventDate].contains(step)
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
        switch step {
        case .raceTime: knowsRaceTime = false
        case .liftEstimates:
            for index in liftEntries.indices { liftEntries[index].isKnown = false }
        case .eventDate: hasEvent = false
        default: break
        }
        next()
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
            units: units
        )
    }

    /// Loads existing answers (used when editing the training profile in Settings).
    func load(_ profile: AthleteProfile) {
        units = profile.units
        runningExperience = profile.runningExperience
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
