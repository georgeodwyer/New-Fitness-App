import Foundation
import SwiftData
import UserNotifications
import TrainingEngine

/// Everything planned ahead: the morning summary, session reminders, fuelling, the check-in
/// nudge, reviews, the evening preview, bedtime and "keep on track" nudges. All local, built
/// for the next week and re-built whenever the app goes to the background or refreshes in the
/// background, so they follow the plan. At most `NotificationBudget.dailyCap` a day: the most
/// useful win.
///
/// Times only appear in the text when the runner set when they usually train (Settings);
/// otherwise it's "Intervals this morning", "Push this evening".
@MainActor
enum TrainingNotifications {
    private static let prefix = "training."

    enum Keys {
        static let sessionEnabled = "notifications.session.enabled"
        static let sessionLead = "notifications.session.leadMinutes"
        static let morningSessionMinutes = "notifications.session.morningAt"
        static let eveningSessionMinutes = "notifications.session.eveningAt"
        static let bedtimeEnabled = "notifications.bedtime.enabled"
        static let sleepNeedMinutes = "notifications.bedtime.sleepNeed"
        static let fuellingEnabled = "notifications.fuelling.enabled"
        static let checkInEnabled = "notifications.checkIn.enabled"
        static let weeklyEnabled = "notifications.weekly.enabled"
        static let resultsEnabled = "notifications.results.enabled"
        static let nudgesEnabled = "notifications.nudges.enabled"
        static let onTrackEnabled = "notifications.onTrack.enabled"
        /// When the app was last opened.
        static let lastOpened = "app.lastOpenedAt"
        static let budgetPrefix = "notifications.budget."
        static let monthlyPrefix = "notifications.monthly."
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
    private static func int(_ key: String, _ fallback: Int) -> Int { UserDefaults.standard.object(forKey: key) as? Int ?? fallback }

    static var sessionEnabled: Bool { bool(Keys.sessionEnabled, true) }
    static var sessionLead: Int { int(Keys.sessionLead, 60) }
    /// When morning and evening sessions usually start (minutes after midnight).
    static var morningSessionMinutes: Int { int(Keys.morningSessionMinutes, 7 * 60) }
    static var eveningSessionMinutes: Int { int(Keys.eveningSessionMinutes, 18 * 60) }
    /// They've told Kinetix when they usually train, so reminders can be timed to sessions.
    static var sessionTimesSet: Bool {
        UserDefaults.standard.object(forKey: Keys.morningSessionMinutes) != nil
            || UserDefaults.standard.object(forKey: Keys.eveningSessionMinutes) != nil
    }
    static var bedtimeEnabled: Bool { bool(Keys.bedtimeEnabled, false) }
    static var sleepNeedMinutes: Int { int(Keys.sleepNeedMinutes, 8 * 60) }
    static var fuellingEnabled: Bool { bool(Keys.fuellingEnabled, true) }
    static var checkInEnabled: Bool { bool(Keys.checkInEnabled, true) }
    static var weeklyEnabled: Bool { bool(Keys.weeklyEnabled, true) }
    /// Run and gym results, personal bests, weights going up, badges, imported runs.
    static var resultsEnabled: Bool { bool(Keys.resultsEnabled, true) }
    /// Recovery heads-up, steps, exertion, tomorrow's preview.
    static var nudgesEnabled: Bool { bool(Keys.nudgesEnabled, true) }
    /// A few days without training, a week away, a check-in streak at risk.
    static var onTrackEnabled: Bool { bool(Keys.onTrackEnabled, true) }

    /// Most important first (see `NotificationBudget`).
    enum Priority {
        static let morning = 0
        static let sessionBefore = 1
        static let stillToDo = 2
        static let fuel = 3
        static let resume = 3
        static let checkIn = 4
        static let streak = 5
        static let weekly = 6
        static let monthly = 7
        static let preview = 8
        static let protein = 9
        static let bedtime = 10
        static let onTrack = 11
        /// Sent from background refresh (recovery heads-up, steps, exertion).
        static let live = 9
    }

    /// When a session starts on its day (from its slot).
    static func startTime(of session: PlannedSessionModel, calendar: Calendar = .kinetix) -> Date {
        let minutes = session.slot == .evening ? eveningSessionMinutes : morningSessionMinutes
        return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: session.date)) ?? session.date
    }

    /// "Intervals this morning" / "Push this evening".
    static func phrase(_ session: PlannedSessionModel) -> String {
        "\(session.title) \(session.slot == .evening ? "this evening" : "this morning")"
    }

    /// Asleep-by time for the night before `day`: enough sleep before tomorrow's first session
    /// (or a 7:00 wake-up), 30 minutes earlier before a hard or long one, never later than midnight.
    static func asleepBy(before firstSession: Date?, hard: Bool, wakeDefault: Int = 7 * 60, sleepNeed: Int,
                         day: Date, calendar: Calendar = .kinetix) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        // Up 45 minutes before an early session; otherwise the usual wake time.
        var wake = calendar.date(byAdding: .minute, value: wakeDefault, to: dayStart) ?? dayStart
        if let firstSession {
            let ready = firstSession.addingTimeInterval(-45 * 60)
            if ready < wake { wake = ready }
        }
        var asleep = wake.addingTimeInterval(-Double(sleepNeed) * 60)
        if hard { asleep = asleep.addingTimeInterval(-30 * 60) }
        return min(asleep, dayStart)
    }

    /// One notification that might be sent.
    struct Pending {
        var id: String
        var date: Date
        var title: String
        var body: String
        var thread: String
        var priority: Int
    }

    static func schedule(in context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        // Also clears the older morning summaries, which used their own prefix.
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(prefix) || $0.hasPrefix("morning.") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        let candidates = build(in: context, now: now, calendar: calendar)

        // Count those already due today too (the morning summary may have gone out), so the cap holds.
        // Live nudges already sent today take their share too.
        let picked = NotificationBudget.pick(candidates.map {
            NotificationBudget.Candidate(id: $0.id, day: calendar.startOfDay(for: $0.date), priority: $0.priority)
        }, used: [today: ActivityNotifications.liveCount(on: today)])
        let counts = NotificationBudget.countByDay(candidates.map {
            NotificationBudget.Candidate(id: $0.id, day: calendar.startOfDay(for: $0.date), priority: $0.priority)
        }, picked: picked)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            UserDefaults.standard.set(counts[day] ?? 0, forKey: Keys.budgetPrefix + "\(Int(day.timeIntervalSince1970))")
        }

        for item in candidates where picked.contains(item.id) && item.date > now {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.thread
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            try? await center.add(UNNotificationRequest(identifier: prefix + item.id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    /// Notifications planned for `day` so far (for those sent later from background refresh).
    static func plannedCount(on day: Date) -> Int {
        UserDefaults.standard.integer(forKey: Keys.budgetPrefix + "\(Int(Calendar.kinetix.startOfDay(for: day).timeIntervalSince1970))")
    }

    // MARK: Building

    private static func build(in context: ModelContext, now: Date, calendar: Calendar) -> [Pending] {
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 8, to: today),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }

        let plan = PlanService.activePlan(in: context)
        let paused = plan?.isPaused == true
        let planSessions = (plan?.sessions ?? []).filter { !$0.isSoftDeleted }
        let sessions = planSessions
            .filter { $0.date >= today && $0.date < end && ($0.status == .planned || $0.status == .swapped) }
            .sorted { ($0.date, $0.slot == .evening ? 1 : 0) < ($1.date, $1.slot == .evening ? 1 : 0) }
        let profileModel = all(UserProfileModel.self).first { !$0.isSoftDeleted }
        let eventDate = profileModel?.eventDate
        let runs = all(RunLogModel.self).filter { $0.isFinished && !$0.isSoftDeleted }
        let lifts = all(StrengthLogModel.self).filter { $0.isFinished && !$0.isSoftDeleted }
        let checkInDays = Set(all(RecoveryCheckInModel.self).filter { !$0.isSoftDeleted }.map { calendar.startOfDay(for: $0.date) })

        var result: [Pending] = []
        func add(_ id: String, at date: Date, _ title: String, _ body: String, thread: String, priority: Int) {
            result.append(Pending(id: id, date: date, title: title, body: body, thread: thread, priority: priority))
        }
        func at(_ day: Date, _ minutes: Int) -> Date { calendar.date(byAdding: .minute, value: minutes, to: day) ?? day }

        // Paused with a return date: a nudge that morning. Nothing else while paused.
        if paused, let until = plan?.pauseUntil {
            add("resume", at: at(calendar.startOfDay(for: until), 9 * 60), "Ready to pick your plan back up?",
                "Open Kinetix and tap Resume when you feel ready. Your plan picks up where you left off.", thread: "plan", priority: Priority.resume)
        }

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            let key = "\(Int(day.timeIntervalSince1970))"
            let onDay = paused ? [] : sessions.filter { calendar.isDate($0.date, inSameDayAs: day) }

            // Morning summary.
            if NotificationService.morningEnabled, plan != nil, !paused {
                let morning = morningContent(day: day, offset: offset, sessions: onDay, planSessions: planSessions, plan: plan,
                                             profile: profileModel?.profile, eventDate: eventDate, yesterday: yesterday,
                                             context: context, now: now, calendar: calendar)
                add("morning.\(key)", at: at(day, NotificationService.morningMinutes), morning.title, morning.body,
                    thread: "morning", priority: Priority.morning)
            }

            for session in onDay {
                let minutes = session.plannedDurationMinutes
                // Before the session: only when they've said when they train.
                if sessionEnabled, sessionTimesSet {
                    var body = "\(session.summary) · \(Int(minutes)) min."
                    if session.kind.discipline == .run && minutes >= 75 && fuellingEnabled {
                        body += " Over 75 min: take a gel or drink with carbs every 30–45 min."
                    } else if session.kind.discipline == .run {
                        body += " Bring a drink if it's warm."
                    }
                    add("session.\(session.id)", at: startTime(of: session).addingTimeInterval(-Double(sessionLead) * 60),
                        "\(session.title) in \(leadText)", body, thread: "session", priority: Priority.sessionBefore)
                }
                // Protein after the gym (timed sessions only; otherwise it comes with the workout result).
                if fuellingEnabled, sessionTimesSet, session.kind.discipline == .strength {
                    add("protein.\(session.id)", at: startTime(of: session).addingTimeInterval((minutes + 15) * 60),
                        "Refuel after the gym", "Have some protein in the next hour or two (around 20–40 g) to help your muscles recover.",
                        thread: "fuel", priority: Priority.protein)
                }
            }

            // Still to do in the evening (cancelled once done).
            if sessionEnabled, !onDay.isEmpty {
                let names = onDay.map(\.title).joined(separator: " and ")
                add("todo.\(key)", at: at(day, 20 * 60 + 30), "\(names) still to do today",
                    "Fit it in this evening, or move it to another day in Kinetix.", thread: "session", priority: Priority.stillToDo)
            }

            // Fuelling: carbs the evening before a long run or race.
            if fuellingEnabled, !paused {
                let tomorrowSessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: tomorrow) }
                let isRace = eventDate.map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false
                if isRace || tomorrowSessions.contains(where: { $0.kind == .run(.long) && $0.plannedDurationMinutes >= 90 }) {
                    add("fuel.\(key)", at: at(day, 19 * 60), isRace ? "Race tomorrow: fuel up tonight" : "Long run tomorrow",
                        "Make tonight's meal a carb-rich one (rice, pasta, potatoes, bread) and drink well. Breakfast 2–3 hours before you start.",
                        thread: "fuel", priority: Priority.fuel)
                }
            }

            // Check-in nudge at 10:00 (cancelled once it's done).
            if checkInEnabled, !checkInDays.contains(day) {
                add("checkin.\(key)", at: at(day, 10 * 60), "How are you feeling?",
                    "A 10-second check-in keeps today's recovery score and plan right for you.", thread: "checkin", priority: Priority.checkIn)
            }

            // Check-in streak at risk (today only: tomorrow depends on today).
            if onTrackEnabled, offset == 0, !checkInDays.contains(day) {
                let streak = checkInStreak(endingBefore: day, days: checkInDays, calendar: calendar)
                if streak >= 3 {
                    add("streak.\(key)", at: at(day, 20 * 60), "Keep your \(streak)-day streak going",
                        "Check in today to keep it. It takes 10 seconds.", thread: "checkin", priority: Priority.streak)
                }
            }

            // Sunday review at 18:00.
            if weeklyEnabled, calendar.weekday(of: day) == .sunday {
                var body = "See how your week went and what's coming next."
                if let review = WeeklyReviewData.make(in: context, now: day.addingTimeInterval(17 * 3600)) {
                    body = review.review.headline + " Tap to see next week."
                }
                add("weekly.\(key)", at: at(day, 18 * 60), "Your week", body, thread: "weekly", priority: Priority.weekly)
            }

            // Tomorrow's preview in the evening.
            if nudgesEnabled, !paused {
                let next = sessions.filter { calendar.isDate($0.date, inSameDayAs: tomorrow) }
                if !next.isEmpty {
                    let total = Int(next.reduce(0) { $0 + $1.plannedDurationMinutes })
                    add("preview.\(key)", at: at(day, 21 * 60), "Tomorrow: " + next.map(\.title).joined(separator: " + "),
                        "About \(durationText(total)) in total. " + next.map { "\($0.title): \($0.summary)" }.joined(separator: ". ") + ".",
                        thread: "preview", priority: Priority.preview)
                }
            }

            // Bedtime the night before.
            if bedtimeEnabled {
                let tomorrowSessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: tomorrow) }
                let hard = tomorrowSessions.contains { $0.plannedEffort >= 7 || $0.kind == .run(.long) }
                let reason = tomorrowSessions.first.map { " before tomorrow's \($0.title.lowercased())" } ?? ""
                if sessionTimesSet {
                    let first = tomorrowSessions.first.map { startTime(of: $0) }
                    let asleep = asleepBy(before: first, hard: hard, sleepNeed: sleepNeedMinutes, day: tomorrow)
                    add("bed.\(key)", at: asleep.addingTimeInterval(-30 * 60), "Time to wind down",
                        "Aim to be asleep by \(asleep.formatted(date: .omitted, time: .shortened))\(reason).", thread: "bedtime", priority: Priority.bedtime)
                } else {
                    add("bed.\(key)", at: at(day, 21 * 60 + 30), "Time to wind down",
                        "Aim for \(durationText(sleepNeedMinutes + (hard ? 30 : 0))) of sleep\(reason).",
                        thread: "bedtime", priority: Priority.bedtime)
                }
            }
        }

        // Monthly round-up, in the first week of the month.
        if weeklyEnabled, let monthly = monthlyRoundUp(runs: runs, lifts: lifts, context: context, now: now, calendar: calendar) {
            add(monthly.id, at: monthly.date, monthly.title, monthly.body, thread: "weekly", priority: Priority.monthly)
        }

        // Keep on track.
        if onTrackEnabled, plan != nil, !paused {
            // Three days without training.
            let last = (runs.map(\.startedAt) + lifts.map(\.startedAt)).max()
            if let last, let due = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: last)) {
                let fire = at(due, 9 * 60 + 30)
                let next = sessions.first { calendar.isDate($0.date, inSameDayAs: due) }
                let body = next.map { "Today: \(phrase($0)). A good one to get going again." } ?? "An easy session today gets you going again."
                add("idle.\(Int(due.timeIntervalSince1970))", at: fire, "Your plan's waiting", body, thread: "onTrack", priority: Priority.onTrack)
            }
            // A week without opening Kinetix.
            let opened = UserDefaults.standard.object(forKey: Keys.lastOpened) as? Date ?? now
            if let away = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: opened)) {
                add("away.\(Int(away.timeIntervalSince1970))", at: at(away, 18 * 60), "Pick up where you left off",
                    "Your plan is ready when you are. If life's busy, you can pause it in the Plan tab.", thread: "onTrack", priority: Priority.onTrack)
            }
        }
        return result
    }

    /// The morning summary: today's sessions, plus what's worth knowing that day.
    private static func morningContent(day: Date, offset: Int, sessions: [PlannedSessionModel], planSessions: [PlannedSessionModel],
                                       plan: TrainingPlanModel?, profile: AthleteProfile?, eventDate: Date?, yesterday: Date,
                                       context: ModelContext, now: Date, calendar: Calendar) -> (title: String, body: String) {
        var lines: [String] = []
        let units = profile?.units ?? UnitPreference.stored
        let format = DisplayFormat(units: units)

        // Last night's recovery, once it's in (refreshed in the background).
        if offset == 0, let recovery = BalanceService.todaysRecovery(in: context, now: now) {
            let score = Int(recovery.score.rounded())
            if let change = recovery.volumeChangeText, recovery.volumeMultiplier < 1, !sessions.isEmpty {
                lines.append("Recovery \(score). Your sessions can be \(change.replacingOccurrences(of: " less", with: " shorter")) when you start them.")
            } else {
                lines.append("Recovery \(score): \(recovery.band.title.lowercased()).")
            }
        }
        for session in sessions {
            lines.append("\(session.title): \(session.summary) · \(Int(session.plannedDurationMinutes)) min")
        }
        // Missed yesterday (today's summary only: earlier days are certain).
        if offset == 0 {
            let missed = planSessions.filter { calendar.isDate($0.date, inSameDayAs: yesterday) && $0.status == .planned }
            if let first = missed.first {
                lines.append("Yesterday's \(first.title.lowercased()) didn't happen. Move it or skip it in Kinetix.")
            }
        }
        // Monday: the week ahead.
        if calendar.weekday(of: day) == .monday, let weekEnd = calendar.date(byAdding: .day, value: 7, to: day) {
            let week = planSessions.filter { $0.date >= day && $0.date < weekEnd && $0.status != .skipped }
            let runs = week.filter { $0.kind.discipline == .run }
            let gym = week.filter { $0.kind.discipline == .strength }
            var text = "This week: \(runs.count) run\(runs.count == 1 ? "" : "s")"
            let meters = runs.compactMap(\.estimatedDistanceMeters).reduce(0, +)
            if meters > 0 { text += " (\(format.distance(meters, decimals: 0)))" }
            text += " and \(gym.count) gym session\(gym.count == 1 ? "" : "s")"
            if let outline = plan?.outline, let index = outline.weekIndex(containing: day, calendar: calendar) {
                let target = outline.weeks[index]
                text += target.isRecoveryWeek ? " · a lighter week to let the work sink in" : " · \(target.phase.displayName) week \(target.weekInPhase + 1)"
            }
            lines.append(text + ".")
        }
        // Thursday: how the week's going (only while it's fresh).
        if calendar.weekday(of: day) == .thursday, offset <= 1 {
            let monday = calendar.startOfISOWeek(for: day)
            let soFar = planSessions.filter { $0.date >= monday && $0.date < day }
            if !soFar.isEmpty {
                let done = soFar.filter { $0.status == .completed }.count
                let total = planSessions.filter { $0.date >= monday && $0.date < (calendar.date(byAdding: .day, value: 7, to: monday) ?? day) }.count
                lines.append("So far this week: \(done) of \(total) sessions done.")
            }
        }
        // Race countdown.
        if let eventDate, let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: eventDate)).day, (2...14).contains(days) {
            lines.append("Race in \(days) days.")
        }
        // Fresh news: a plan change, or faster paces to take up.
        if offset <= 1 {
            let recent = ((try? context.fetch(FetchDescriptor<PlanChangeModel>())) ?? [])
                .filter { !$0.isSoftDeleted && $0.createdAt > now.addingTimeInterval(-2 * 86_400) }
                .max { $0.createdAt < $1.createdAt }
            if let recent, let sentence = recent.summary.split(separator: ".").first {
                lines.append(String(sentence) + ".")
            }
            if let profile, FormService.shouldOfferPaceUpdate(for: profile) {
                lines.append("Your recent runs show you're fitter: update your paces in Kinetix.")
            }
        }

        if sessions.isEmpty {
            return ("Rest day", (["Nothing planned today. Recovery is when the training sinks in."] + lines).joined(separator: "\n"))
        }
        return ("Today: " + sessions.map(phrase).joined(separator: ", "), lines.joined(separator: "\n"))
    }

    /// Days in a row with a check-in, up to the day before `day`.
    private static func checkInStreak(endingBefore day: Date, days: Set<Date>, calendar: Calendar) -> Int {
        var count = 0
        var cursor = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Last month in numbers, sent once in the first week of the month at 18:30.
    private static func monthlyRoundUp(runs: [RunLogModel], lifts: [StrengthLogModel], context: ModelContext, now: Date,
                                       calendar: Calendar) -> Pending? {
        let today = calendar.startOfDay(for: now)
        guard calendar.component(.day, from: today) <= 7,
              let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
              let lastMonth = calendar.date(byAdding: .month, value: -1, to: monthStart) else { return nil }
        let key = Keys.monthlyPrefix + "\(Int(lastMonth.timeIntervalSince1970))"
        // Already planned for a time that has passed: it's been sent.
        if let planned = UserDefaults.standard.object(forKey: key) as? Date, planned <= now { return nil }
        var fire = calendar.date(byAdding: .minute, value: 18 * 60 + 30, to: today) ?? today
        if fire <= now { fire = calendar.date(byAdding: .day, value: 1, to: fire) ?? fire }
        guard calendar.component(.day, from: fire) <= 7 else { return nil }

        let inMonth = { (date: Date) in date >= lastMonth && date < monthStart }
        let meters = runs.filter { $0.countsTowardsHistory && inMonth($0.startedAt) }.reduce(0) { $0 + $1.distanceMeters }
            + lifts.filter { inMonth($0.startedAt) }.reduce(0) { $0 + $1.functionalRunMeters }
        let gym = lifts.filter { inMonth($0.startedAt) && !$0.isFunctional }.count
        let records = Set(((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
            .filter { !$0.isSoftDeleted && inMonth($0.achievedAt) }.map(\.recordKey)).count
        guard meters > 0 || gym > 0 else { return nil }
        UserDefaults.standard.set(fire, forKey: key)
        let units = (try? context.fetch(FetchDescriptor<UserProfileModel>()))?.first?.units ?? UnitPreference.stored
        let name = lastMonth.formatted(.dateTime.month(.wide))
        var parts = ["\(DisplayFormat(units: units).distance(meters, decimals: 0)) run", "\(gym) gym session\(gym == 1 ? "" : "s")"]
        if records > 0 { parts.append("\(records) new best\(records == 1 ? "" : "s")") }
        return Pending(id: "monthly.\(Int(lastMonth.timeIntervalSince1970))", date: fire, title: "\(name) in numbers",
                       body: parts.joined(separator: ", ") + ". Tap to see your progress.", thread: "weekly", priority: Priority.monthly)
    }

    // MARK: Done

    /// Today's check-in is done: no nudge, no streak warning.
    static func checkInDone(now: Date = .now) {
        let day = Calendar.kinetix.startOfDay(for: now)
        let key = "\(Int(day.timeIntervalSince1970))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + "checkin.\(key)", prefix + "streak.\(key)"])
    }

    /// A session was done: no "still to do" for its day.
    static func sessionDone(on date: Date) {
        let day = Calendar.kinetix.startOfDay(for: date)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + "todo.\(Int(day.timeIntervalSince1970))"])
    }

    /// "1 h 50 min", "45 min", "8 h".
    static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private static var leadText: String {
        let lead = sessionLead
        if lead % 60 == 0 { return lead == 60 ? "1 hour" : "\(lead / 60) hours" }
        return "\(lead) min"
    }
}
