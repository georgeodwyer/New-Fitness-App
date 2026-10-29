import Foundation
import SwiftData
import UserNotifications
import TrainingEngine

/// Local notifications: a morning summary of the day's sessions, and "rest's up" when the
/// phone is locked during a gym rest. Nothing is sent from a server.
@MainActor
enum NotificationService {
    private static let morningPrefix = "morning."
    private static let restID = "gym.rest"

    enum Keys {
        static let morningEnabled = "notifications.morning.enabled"
        static let morningMinutes = "notifications.morning.minutes"
        static let restEnabled = "notifications.rest.enabled"
    }

    static var morningEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.morningEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.morningEnabled) }
    }

    /// Minutes after midnight (default 07:00).
    static var morningMinutes: Int {
        get { UserDefaults.standard.object(forKey: Keys.morningMinutes) as? Int ?? 7 * 60 }
        set { UserDefaults.standard.set(newValue, forKey: Keys.morningMinutes) }
    }

    static var restEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.restEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.restEnabled) }
    }

    /// Asks once, at a moment it makes sense (after building a plan or switching one on).
    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: Morning summary

    /// Re-schedules the next seven mornings from the plan (call when the app goes to the
    /// background, so changes to the plan are picked up).
    static func scheduleMornings(in context: ModelContext, now: Date = .now) async {
        await TrainingNotifications.schedule(in: context, now: now)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(morningPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard morningEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 8, to: today) else { return }
        let descriptor = FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.date >= today && $0.date < end })
        let sessions = ((try? context.fetch(descriptor)) ?? []).filter { !$0.isSoftDeleted && $0.plan?.isActive != false }
        guard !sessions.isEmpty else { return }

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(byAdding: .minute, value: morningMinutes, to: day), fire > now else { continue }
            let onDay = sessions.filter { calendar.isDate($0.date, inSameDayAs: day) && $0.status != .skipped }
                .sorted { $0.slot == .morning && $1.slot == .evening }
            let content = UNMutableNotificationContent()
            if onDay.isEmpty {
                content.title = "Rest day"
                content.body = "Nothing planned today. Recovery is when the training sinks in."
            } else {
                content.title = "Today: " + onDay.map(\.title).joined(separator: " + ")
                content.body = onDay.map { "\($0.summary) \u{00B7} \(Int($0.plannedDurationMinutes)) min" }.joined(separator: "\n")
                    + "\nOpen Kinetix to see your recovery and today's target."
            }
            content.sound = .default
            content.threadIdentifier = "morning"
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = morningPrefix + ISO8601DateFormatter().string(from: day)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    // MARK: Rest timer

    /// "Rest's up" at the end of a gym rest, for when the phone is locked.
    static func scheduleRestEnd(at end: Date, next: String?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restID])
        guard restEnabled, end.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = next.map { "Next: \($0)" } ?? "Time for your next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: restID, content: content, trigger: trigger))
    }

    static func cancelRest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restID])
    }
}
