import Foundation
import SwiftData
import UserNotifications
import TrainingEngine

/// Sent as things happen:
/// - a finished workout with its result, new bests, weights going up and badges (only shows
///   when Kinetix isn't on screen, e.g. a run finished on the watch with the phone in a pocket);
/// - runs from other apps arriving through Apple Health;
/// - the day's live nudges, found by background refresh: recovery when it's low, steps in the
///   afternoon, exertion in the evening.
/// Workout results and imported runs always come through; the live nudges count towards the
/// daily limit with the planned notifications.
@MainActor
enum ActivityNotifications {
    private static let prefix = "activity."

    private enum Keys {
        static let livePrefix = "notifications.live."
        static let sentPrefix = "notifications.sent."
        static let seenWorkouts = "notifications.seenWorkouts"
    }

    // MARK: Sending

    /// Live nudges sent on `day` (they count towards the daily limit).
    static func liveCount(on day: Date) -> Int {
        UserDefaults.standard.integer(forKey: Keys.livePrefix + "\(Int(Calendar.kinetix.startOfDay(for: day).timeIntervalSince1970))")
    }

    @discardableResult
    private static func post(_ id: String, title: String, body: String, thread: String, capped: Bool, now: Date = .now) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return false }
        if capped {
            let used = TrainingNotifications.plannedCount(on: now) + liveCount(on: now)
            guard used < NotificationBudget.dailyCap else { return false }
            let key = Keys.livePrefix + "\(Int(Calendar.kinetix.startOfDay(for: now).timeIntervalSince1970))"
            UserDefaults.standard.set(liveCount(on: now) + 1, forKey: key)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
        try? await center.add(UNNotificationRequest(identifier: prefix + id, content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        return true
    }

    /// Whether `key` was already marked sent.
    private static func sent(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: Keys.sentPrefix + key) }
    private static func markSent(_ key: String) { UserDefaults.standard.set(true, forKey: Keys.sentPrefix + key) }

    // MARK: Workout results

    /// Not while unit tests run: the queued work would outlive each test's throwaway store.
    static let isActive = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    /// After a run is saved: its result, then the week's notifications brought up to date.
    static func afterRunSaved(_ id: UUID, in context: ModelContext) {
        guard isActive else { return }
        Task { @MainActor in
            await runFinished(id: id, in: context)
            await NotificationService.scheduleMornings(in: context)
        }
    }

    /// After a gym or functional session is saved.
    static func afterGymSaved(_ id: UUID, summary: StrengthService.Summary?, in context: ModelContext) {
        guard isActive else { return }
        Task { @MainActor in
            await gymFinished(id: id, summary: summary, in: context)
            await NotificationService.scheduleMornings(in: context)
        }
    }

    /// Called a moment after saving (from a Task), so the workout is looked up again by id: the
    /// object saved may no longer be usable by then (deleted, or the store reset).
    static func runFinished(id: UUID, in context: ModelContext) async {
        let descriptor = FetchDescriptor<RunLogModel>(predicate: #Predicate { $0.id == id })
        guard let log = (try? context.fetch(descriptor))?.first, log.isFinished else { return }
        await runFinished(log, in: context)
    }

    static func gymFinished(id: UUID, summary: StrengthService.Summary?, in context: ModelContext) async {
        let descriptor = FetchDescriptor<StrengthLogModel>(predicate: #Predicate { $0.id == id })
        guard let log = (try? context.fetch(descriptor))?.first else { return }
        await gymFinished(log, summary: summary, in: context)
    }

    /// A run was saved: its result, new best efforts and badges.
    static func runFinished(_ log: RunLogModel, in context: ModelContext) async {
        TrainingNotifications.sessionDone(on: log.startedAt)
        guard TrainingNotifications.resultsEnabled, log.distanceMeters > 0 else { return }
        let units = profileUnits(in: context)
        let format = DisplayFormat(units: units)
        var lines: [String] = []
        var headline = "\(format.distance(log.distanceMeters, decimals: 2)) in \(Units.formatMinutesSeconds(log.durationSeconds))"
        if log.distanceMeters >= 500 {
            headline += " · " + format.pace(Pace(secondsPerKm: log.durationSeconds / (log.distanceMeters / 1000)))
        }
        lines.append(headline + ".")
        lines += newRunBests(log, in: context)
        lines += newBadges(excludingRun: log.id, in: context).map { "Badge earned: \($0)." }
        await post("run.\(log.id)", title: "Run done: \(log.title.isEmpty ? "Run" : log.title)", body: lines.joined(separator: "\n"),
                   thread: "results", capped: false)
    }

    /// A gym or functional session was saved: what it was, weights going up, new bests and badges.
    static func gymFinished(_ log: StrengthLogModel, summary: StrengthService.Summary?, in context: ModelContext) async {
        TrainingNotifications.sessionDone(on: log.startedAt)
        guard TrainingNotifications.resultsEnabled else { return }
        var lines: [String] = []
        let minutes = Int((log.durationSeconds / 60).rounded())
        if let summary {
            lines.append("\(summary.completedSets) sets in \(TrainingNotifications.durationText(minutes)).")
            for change in summary.changes {
                if case .increase = change.change, let first = change.reason.split(separator: ".").first {
                    lines.append(String(first) + ".")
                }
            }
            for record in summary.records {
                lines.append("New best: \(record.exerciseName) (\(record.record.kind.displayName.lowercased())).")
            }
        } else {
            lines.append("Done in \(TrainingNotifications.durationText(minutes)).")
        }
        lines += newBadges(excludingLift: log.id, in: context).map { "Badge earned: \($0)." }
        if TrainingNotifications.fuellingEnabled, !log.isFunctional {
            lines.append("Have some protein in the next hour or two to help your muscles recover.")
        }
        await post("gym.\(log.id)", title: "\(log.title.isEmpty ? "Workout" : log.title) done", body: lines.joined(separator: "\n"),
                   thread: "results", capped: false)
    }

    /// "New best: 5K in 22:41", for each standard distance this run beat.
    private static func newRunBests(_ log: RunLogModel, in context: ModelContext) -> [String] {
        guard log.distanceMeters >= BestEffortDistance.oneKilometre.meters, !log.isImportedFromStrava else { return [] }
        let mine = RunAnalysis.bestEfforts(route: log.route)
        guard !mine.isEmpty else { return [] }
        let others = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
            .filter { $0.isFinished && !$0.isSoftDeleted && $0.id != log.id && !$0.usedSimulatedGPS && !$0.isImportedFromStrava
                && $0.distanceMeters >= BestEffortDistance.oneKilometre.meters }
        // A first run sets bests quietly: nothing to beat yet.
        guard !others.isEmpty else { return [] }
        var previous: [BestEffortDistance: Double] = [:]
        for run in others {
            for (distance, seconds) in RunAnalysis.bestEfforts(route: run.route) where previous[distance].map({ seconds < $0 }) ?? true {
                previous[distance] = seconds
            }
        }
        return BestEffortDistance.allCases.compactMap { distance in
            guard let seconds = mine[distance], let old = previous[distance], seconds < old - 0.5 else { return nil }
            return "New best: \(distance.displayName) in \(Units.formatMinutesSeconds(seconds))."
        }
    }

    /// Badges this workout earned.
    private static func newBadges(excludingRun runId: UUID? = nil, excludingLift liftId: UUID? = nil, in context: ModelContext) -> [String] {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let checkIns = all(RecoveryCheckInModel.self).filter { !$0.isSoftDeleted }.count
        let runs = all(RunLogModel.self).filter { $0.isFinished && !$0.isSoftDeleted && !$0.usedSimulatedGPS }
        let lifts = all(StrengthLogModel.self).filter { $0.isFinished && !$0.isSoftDeleted }
        let records = all(PersonalRecordModel.self).filter { !$0.isSoftDeleted }.count
        func stats(runs: [RunLogModel], lifts: [StrengthLogModel]) -> AchievementStats {
            let functional = lifts.filter(\.isFunctional)
            let calendar = Calendar.kinetix
            return AchievementStats(
                checkIns: checkIns, runs: runs.count,
                runMeters: runs.reduce(0) { $0 + $1.distanceMeters } + functional.reduce(0) { $0 + $1.functionalRunMeters },
                gymSessions: lifts.filter { !$0.isFunctional && !$0.isManual }.count, functionalWorkouts: functional.count,
                personalRecords: records, trainingDays: (runs.map(\.startedAt) + lifts.map(\.startedAt)).map { calendar.startOfDay(for: $0) })
        }
        let before = Achievements.make(stats(runs: runs.filter { $0.id != runId }, lifts: lifts.filter { $0.id != liftId }))
        let after = Achievements.make(stats(runs: runs, lifts: lifts))
        return Achievements.newlyEarned(before: before, after: after)
    }

    // MARK: Runs from other apps

    /// Runs from other apps (a Garmin, another watch app) that arrived through Apple Health and
    /// aren't Kinetix's own: "Your run from Garmin is in".
    static func importedRuns(in context: ModelContext, now: Date = .now) async {
        let settings = IntegrationSettings.shared
        guard settings.healthEnabled else { return }
        let runs = settings.externalWorkouts.filter { $0.kind == .run && $0.start > now.addingTimeInterval(-2 * 86_400) }
        let defaults = UserDefaults.standard
        let seenBefore = defaults.stringArray(forKey: Keys.seenWorkouts)
        var seen = Set(seenBefore ?? [])
        defer { defaults.set(Array(seen.suffix(200)), forKey: Keys.seenWorkouts) }
        // The first time: just note what's there, so nobody gets a pile of old runs.
        guard seenBefore != nil else {
            seen.formUnion(settings.externalWorkouts.map(\.id.uuidString))
            return
        }
        let recorded = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
            .filter { $0.isFinished && !$0.isSoftDeleted }
            .map { DateInterval(start: $0.startedAt, duration: max($0.durationSeconds, 1)) }
        let fresh = ExternalWorkouts.notRecorded(runs, excluding: recorded).filter { !seen.contains($0.id.uuidString) }
        seen.formUnion(runs.map(\.id.uuidString))
        guard TrainingNotifications.resultsEnabled else { return }
        let format = DisplayFormat(units: profileUnits(in: context))
        for run in fresh {
            let day = run.start.formatted(.dateTime.weekday(.wide))
            let distance = run.distanceMeters.map { format.distance($0, decimals: 1) } ?? "Your run"
            await post("import.\(run.id)", title: "Your run from \(run.name) is in",
                       body: "\(distance) on \(day). It counts towards your week.", thread: "results", capped: false)
        }
    }

    // MARK: Live nudges

    /// Checked from background refresh, at most once a day each, within the daily limit.
    static func checkLive(in context: ModelContext, now: Date = .now) async {
        guard TrainingNotifications.nudgesEnabled else { return }
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        let dayKey = "\(Int(today.timeIntervalSince1970))"
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let todaysSessions = (PlanService.activePlan(in: context)?.sessions ?? [])
            .filter { !$0.isSoftDeleted && calendar.isDate($0.date, inSameDayAs: now) && $0.status == .planned }

        // Recovery heads-up: after the morning summary went out without it, low and with a session to come.
        let recoveryKey = "recovery.\(dayKey)"
        if !sent(recoveryKey), minutes > NotificationService.morningMinutes, minutes < 14 * 60, let session = todaysSessions.first,
           let recovery = BalanceService.todaysRecovery(in: context, now: now), recovery.volumeMultiplier < 1,
           let change = recovery.volumeChangeText {
            let score = Int(recovery.score.rounded())
            if await post(recoveryKey, title: "Recovery \(score) today",
                          body: "Your \(session.title.lowercased()) can be \(change.replacingOccurrences(of: " less", with: " shorter")) when you start it.",
                          thread: "nudges", capped: true, now: now) {
                markSent(recoveryKey)
            }
        }

        // Steps in the afternoon: well under their usual by mid-afternoon.
        let stepsKey = "steps.\(dayKey)"
        if !sent(stepsKey), minutes >= 15 * 60, minutes < 17 * 60 + 30 {
            let days = HealthService.shared.metricDays[.steps] ?? []
            let todaySteps = days.first { calendar.isDate($0.date, inSameDayAs: now) }?.value ?? 0
            let recent = days.filter { $0.date < today && $0.date >= today.addingTimeInterval(-14 * 86_400) }.map(\.value).sorted()
            if recent.count >= 5, todaySteps > 0 {
                let usual = recent[recent.count / 2]
                if usual >= 4000, todaySteps < usual * 0.5 {
                    if await post(stepsKey, title: "\(Int(todaySteps).formatted()) steps so far",
                                  body: "A 15-minute walk gets you closer to your usual \(Int(usual).formatted()).",
                                  thread: "nudges", capped: true, now: now) {
                        markSent(stepsKey)
                    }
                }
            }
        }

        // Exertion in the evening: well over today's target, or on target after a session.
        let exertionKey = "exertion.\(dayKey)"
        if !sent(exertionKey), minutes >= 19 * 60 + 30, minutes < 22 * 60 {
            let profile = all(UserProfileModel.self).first { !$0.isSoftDeleted }
            let sessions = all(PlannedSessionModel.self).filter { !$0.isSoftDeleted && ($0.plan?.isActive ?? true) }
            let runs = all(RunLogModel.self), lifts = all(StrengthLogModel.self)
            let data = DashboardService.make(sessions: sessions, runs: runs, lifts: lifts, checkIns: all(RecoveryCheckInModel.self),
                                             profile: profile?.profile, external: IntegrationSettings.shared.loadWorkouts,
                                             health: HealthInputs.current, now: now)
            let strain = Int(data.strain.today.strain.rounded())
            let target = data.strain.target
            let trainedToday = (runs.filter { $0.isFinished && !$0.isSoftDeleted }.map(\.startedAt)
                + lifts.filter { $0.isFinished && !$0.isSoftDeleted }.map(\.startedAt)).contains { calendar.isDate($0, inSameDayAs: now) }
            var message: (String, String)?
            if Double(strain) > target.high + 5 {
                message = ("Big day: exertion \(strain)", "Against a target of \(Int(target.low.rounded()))–\(Int(target.high.rounded())). Keep tomorrow easy.")
            } else if trainedToday, target.contains(Double(strain)) {
                message = ("Exertion \(strain) today", "Right on target. Nicely judged.")
            }
            if let message, await post(exertionKey, title: message.0, body: message.1, thread: "nudges", capped: true, now: now) {
                markSent(exertionKey)
            }
        }
    }

    private static func profileUnits(in context: ModelContext) -> UnitSystem {
        ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.units ?? UnitPreference.stored
    }
}
