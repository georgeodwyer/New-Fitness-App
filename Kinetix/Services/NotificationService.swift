import Foundation
import SwiftData
import UserNotifications
import TrainingEngine

/// Local notifications: permission, the morning summary's settings and "rest's up" when the
/// phone is locked during a gym rest. Nothing is sent from a server. Planned notifications are
/// built in `TrainingNotifications`; workout results and live nudges in `ActivityNotifications`.
@MainActor
enum NotificationService {
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

    // MARK: Planned ahead

    /// Re-schedules the next week of notifications from the plan (call when the app goes to
    /// the background, so changes to the plan are picked up). The morning summary is one of
    /// them (see `TrainingNotifications`).
    static func scheduleMornings(in context: ModelContext, now: Date = .now) async {
        await TrainingNotifications.schedule(in: context, now: now)
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
