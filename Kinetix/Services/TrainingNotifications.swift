import Foundation
import SwiftData
import UserNotifications
import TrainingEngine

/// Session reminders, bedtime, fuelling, the check-in nudge and the Sunday review. All local,
/// re-scheduled with the morning summary whenever the plan changes or the app goes to the
/// background.
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
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
    private static func int(_ key: String, _ fallback: Int) -> Int { UserDefaults.standard.object(forKey: key) as? Int ?? fallback }

    static var sessionEnabled: Bool { bool(Keys.sessionEnabled, true) }
    static var sessionLead: Int { int(Keys.sessionLead, 60) }
    /// When morning and evening sessions usually start (minutes after midnight).
    static var morningSessionMinutes: Int { int(Keys.morningSessionMinutes, 7 * 60) }
    static var eveningSessionMinutes: Int { int(Keys.eveningSessionMinutes, 18 * 60) }
    static var bedtimeEnabled: Bool { bool(Keys.bedtimeEnabled, false) }
    static var sleepNeedMinutes: Int { int(Keys.sleepNeedMinutes, 8 * 60) }
    static var fuellingEnabled: Bool { bool(Keys.fuellingEnabled, true) }
    static var checkInEnabled: Bool { bool(Keys.checkInEnabled, true) }
    static var weeklyEnabled: Bool { bool(Keys.weeklyEnabled, true) }

    /// When a session starts on its day (from its slot).
    static func startTime(of session: PlannedSessionModel, calendar: Calendar = .kinetix) -> Date {
        let minutes = session.slot == .evening ? eveningSessionMinutes : morningSessionMinutes
        return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: session.date)) ?? session.date
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

    static func schedule(in context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 8, to: today) else { return }
        let descriptor = FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.date >= today && $0.date < end })
        let sessions = ((try? context.fetch(descriptor)) ?? [])
            .filter { !$0.isSoftDeleted && $0.plan?.isActive != false && ($0.status == .planned || $0.status == .swapped) }
            .sorted { startTime(of: $0) < startTime(of: $1) }
        let eventDate = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.eventDate

        func add(_ id: String, at date: Date, title: String, body: String, thread: String) async {
            guard date > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = thread
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            try? await center.add(UNNotificationRequest(identifier: prefix + id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }

        for session in sessions {
            let start = startTime(of: session)
            let minutes = session.plannedDurationMinutes
            let isLongRun = session.kind == .run(.long) && minutes >= 90
            let isRace = eventDate.map { calendar.isDate($0, inSameDayAs: session.date) } ?? false
            // Session reminder.
            if sessionEnabled {
                var body = "\(session.summary) · \(Int(minutes)) min."
                if session.kind.discipline == .run && minutes >= 75 && fuellingEnabled {
                    body += " Over 75 min: take a gel or drink with carbs every 30–45 min."
                } else if session.kind.discipline == .run {
                    body += " Bring a drink if it's warm."
                }
                await add("session.\(session.id)", at: start.addingTimeInterval(-Double(sessionLead) * 60),
                          title: "\(session.title) in \(leadText)", body: body, thread: "session")
            }
            // Fuelling: carbs the evening before a long run or race.
            if fuellingEnabled, isLongRun || isRace,
               let evening = calendar.date(byAdding: .hour, value: -5, to: calendar.startOfDay(for: session.date)) {
                await add("fuel.\(session.id)", at: evening, title: isRace ? "Race tomorrow: fuel up tonight" : "Long run tomorrow",
                          body: "Make tonight's meal a carb-rich one (rice, pasta, potatoes, bread) and drink well. Breakfast 2–3 hours before you start.",
                          thread: "fuel")
            }
            // Protein after the gym.
            if fuellingEnabled, session.kind.discipline == .strength {
                await add("protein.\(session.id)", at: start.addingTimeInterval((minutes + 15) * 60),
                          title: "Refuel after the gym", body: "Have some protein in the next hour or two (around 20–40 g) to help your muscles recover.",
                          thread: "fuel")
            }
        }

        // Paused with a return date: a nudge that morning.
        if let plan = PlanService.activePlan(in: context), plan.isPaused, let until = plan.pauseUntil,
           let nine = calendar.date(byAdding: .hour, value: 9, to: calendar.startOfDay(for: until)) {
            await add("resume", at: nine, title: "Ready to pick your plan back up?",
                      body: "Open Kinetix and tap Resume when you feel ready. Your plan picks up where you left off.", thread: "plan")
        }

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // Check-in nudge at 10:00 (cancelled once it's done).
            if checkInEnabled, let ten = calendar.date(byAdding: .hour, value: 10, to: day) {
                await add("checkin.\(Int(day.timeIntervalSince1970))", at: ten, title: "How are you feeling?",
                          body: "A 10-second check-in keeps today's recovery score and plan right for you.", thread: "checkin")
            }
            // Bedtime: the night before each day.
            if bedtimeEnabled, let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) {
                let tomorrowSessions = sessions.filter { calendar.isDate($0.date, inSameDayAs: tomorrow) }
                let first = tomorrowSessions.first.map { startTime(of: $0) }
                let hard = tomorrowSessions.contains { $0.plannedEffort >= 7 || ($0.kind == .run(.long)) }
                let asleep = asleepBy(before: first, hard: hard, sleepNeed: sleepNeedMinutes, day: tomorrow)
                let reason = tomorrowSessions.first.map { " for tomorrow's \($0.title.lowercased())" } ?? ""
                await add("bed.\(Int(day.timeIntervalSince1970))", at: asleep.addingTimeInterval(-30 * 60),
                          title: "Time to wind down",
                          body: "Aim to be asleep by \(asleep.formatted(date: .omitted, time: .shortened))\(reason).", thread: "bedtime")
            }
            // Sunday review at 18:00.
            if weeklyEnabled, calendar.weekday(of: day) == .sunday, let six = calendar.date(byAdding: .hour, value: 18, to: day) {
                var body = "See how your week went and what's coming next."
                if let review = WeeklyReviewData.make(in: context, now: day.addingTimeInterval(17 * 3600)) {
                    body = review.review.headline + " Tap to see next week."
                }
                await add("weekly.\(Int(day.timeIntervalSince1970))", at: six, title: "Your week", body: body, thread: "weekly")
            }
        }
    }

    /// Today's check-in is done: no nudge.
    static func checkInDone(now: Date = .now) {
        let day = Calendar.kinetix.startOfDay(for: now)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + "checkin.\(Int(day.timeIntervalSince1970))"])
    }

    private static var leadText: String {
        let lead = sessionLead
        if lead % 60 == 0 { return lead == 60 ? "1 hour" : "\(lead / 60) hours" }
        return "\(lead) min"
    }
}
