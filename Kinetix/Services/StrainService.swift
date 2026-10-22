import Foundation
import TrainingEngine

/// What Apple Health adds to strain and recovery (all empty when it isn't connected).
/// Only readings from today are passed on, and none until last night's sleep has arrived.
struct HealthInputs {
    var hrv: HRVSignal?
    var restingHeartRate: RestingHeartRateSignal?
    var sleepHours: Double?
    /// Their typical night, which sleep is scored against.
    var usualSleepHours: Double?
    var steps: [HealthDay] = []
    /// Last night's data isn't in yet: no recovery score, and Health can't ease the plan.
    var isWaitingForLastNight = false

    static let none = HealthInputs()

    @MainActor static var current: HealthInputs {
        let health = HealthService.shared
        guard health.isConnected else { return .none }
        // Steps from earlier days are fine for the chart; today's readings only once they're in.
        let steps = health.metricDays[.steps] ?? []
        if health.isWaitingForLastNight {
            return HealthInputs(steps: health.isFreshToday ? steps : steps.filter { !Calendar.kinetix.isDateInToday($0.date) },
                                isWaitingForLastNight: true)
        }
        return HealthInputs(hrv: health.hrv, restingHeartRate: health.restingHeartRate, sleepHours: health.lastNightSleepHours,
                            usualSleepHours: health.usualSleepHours, steps: steps)
    }

    /// Identifies what the plan check has seen today, so it runs again once more data arrives.
    var planCheckKey: String {
        if isWaitingForLastNight { return "waiting" }
        return hrv != nil || restingHeartRate != nil || sleepHours != nil ? "body" : "none"
    }
}

/// Turns recorded sessions, other apps' workouts and Health data into the strain report.
@MainActor
enum StrainService {
    /// The runner's heart-rate zones: their age (or own settings), raised by what their runs show.
    static func zones(profile: AthleteProfile?, runs: [RunLogModel], now: Date = .now) -> HeartRateZones {
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let maxima = runs.filter { $0.isFinished && !$0.isSoftDeleted && $0.startedAt >= yearAgo }.compactMap(\.maxHeartRate)
        return HeartRateZones.make(age: profile?.age(on: now), recordedMax: HeartRateZones.recordedMax(maxima),
                                   settings: profile?.heartRateZones)
    }

    static func activities(runs: [RunLogModel], lifts: [StrengthLogModel], external: [ExternalWorkout],
                           sessions: [PlannedSessionModel], zones: HeartRateZones) -> [StrainActivity] {
        let finishedRuns = runs.filter { $0.isFinished && !$0.isSoftDeleted }
        let finishedLifts = lifts.filter { $0.isFinished && !$0.isSoftDeleted }
        func interval(_ start: Date, _ duration: Double, _ end: Date?) -> DateInterval {
            DateInterval(start: start, duration: max(duration, (end ?? start).timeIntervalSince(start)))
        }
        let recorded = finishedRuns.map { interval($0.startedAt, $0.durationSeconds, $0.finishedAt) }
            + finishedLifts.map { interval($0.startedAt, $0.durationSeconds, $0.finishedAt) }

        var result: [StrainActivity] = []
        for run in finishedRuns {
            let samples = run.heartRateSamples
            var load = Strain.load(samples: samples, zones: zones)
            var usedHeartRate = load > 0
            if !usedHeartRate, let average = run.averageHeartRate, average > 0 {
                load = Strain.load(averageHeartRate: average, durationSeconds: run.durationSeconds, zones: zones)
                usedHeartRate = true
            }
            if !usedHeartRate {
                load = Strain.load(durationSeconds: run.durationSeconds, effort: run.effort > 0 ? run.effort : 5)
            }
            result.append(StrainActivity(id: run.id.uuidString, date: run.startedAt, source: .run,
                                         name: run.title.isEmpty ? "Run" : run.title, load: load, legsShare: 1,
                                         usedHeartRate: usedHeartRate,
                                         steps: StrainActivity.steps(meters: run.distanceMeters, running: true)))
        }
        let plannedById = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for lift in finishedLifts {
            let load = Strain.load(durationSeconds: lift.durationSeconds, effort: lift.effort > 0 ? lift.effort : 6)
            result.append(StrainActivity(id: lift.id.uuidString, date: lift.startedAt, source: .lift,
                                         name: lift.title.isEmpty ? "Gym" : lift.title, load: load,
                                         legsShare: legsShare(of: lift, planned: lift.plannedSessionId.flatMap { plannedById[$0] })))
        }
        for workout in ExternalWorkouts.notRecorded(external, excluding: recorded) {
            let load: Double
            if let average = workout.averageHeartRate, average > 0 {
                load = Strain.load(averageHeartRate: average, durationSeconds: workout.durationSeconds, zones: zones)
            } else {
                load = Strain.load(durationSeconds: workout.durationSeconds, effort: workout.estimatedEffort(maxHeartRate: nil))
            }
            let source: StrainActivity.Source = workout.kind == .run ? .run : workout.kind == .strength ? .lift : .other
            let steps = workout.kind == .run || workout.kind == .walking
                ? StrainActivity.steps(meters: workout.distanceMeters ?? 0, running: workout.kind == .run) : 0
            result.append(StrainActivity(id: workout.id.uuidString, date: workout.start, source: source, name: workout.name,
                                         load: load, legsShare: StrainActivity.legsShare(for: workout.kind),
                                         usedHeartRate: (workout.averageHeartRate ?? 0) > 0, steps: steps))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Share of a gym session's work on the legs: lower-body sets out of all completed sets,
    /// else from the planned session's focus.
    private static func legsShare(of lift: StrengthLogModel, planned: PlannedSessionModel?) -> Double {
        let sets = lift.orderedSets.filter(\.isCompleted)
        let regions = sets.compactMap { PlanService.templates.exercise(id: $0.exerciseId)?.region }
        if !regions.isEmpty {
            return Double(regions.filter { $0 == .lower }.count) / Double(regions.count)
        }
        if case .strength(let focus)? = planned?.kind {
            return focus.loadsLowerBody ? 0.7 : 0.05
        }
        return 0.4
    }

    /// Today's planned sessions that aren't skipped, as load (nil without a plan).
    static func plannedLoadToday(sessions: [PlannedSessionModel], hasPlan: Bool, now: Date = .now) -> Double? {
        guard hasPlan else { return nil }
        let calendar = Calendar.kinetix
        return sessions
            .filter { !$0.isSoftDeleted && ($0.plan?.isActive ?? true) && calendar.isDate($0.date, inSameDayAs: now) && $0.status != .skipped }
            .reduce(0) { $0 + StrainTarget.plannedLoad(minutes: $1.plannedDurationMinutes, effort: $1.plannedEffort) }
    }

    static func report(sessions: [PlannedSessionModel], runs: [RunLogModel], lifts: [StrengthLogModel],
                       checkIn: RecoveryCheckIn?, profile: AthleteProfile?, external: [ExternalWorkout],
                       health: HealthInputs, now: Date = .now) -> StrainReport {
        let zones = zones(profile: profile, runs: runs, now: now)
        // No recovery score until last night's data is in (a partial one would mislead).
        let recovery = health.isWaitingForLastNight ? nil
            : RecoveryScore.make(hrv: health.hrv, restingHeartRate: health.restingHeartRate,
                                 sleepHours: health.sleepHours, usualSleepHours: health.usualSleepHours, checkIn: checkIn)
        return StrainReport.make(
            activities: activities(runs: runs, lifts: lifts, external: external, sessions: sessions, zones: zones),
            steps: health.steps,
            plannedLoadToday: plannedLoadToday(sessions: sessions, hasPlan: profile != nil, now: now),
            recovery: recovery, now: now, calendar: .kinetix)
    }
}
