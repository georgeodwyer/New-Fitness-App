import SwiftUI
import SwiftData
import UserNotifications

/// On Today, for anyone without notifications on: what they'd get, then Apple's question (if
/// they've never been asked) or a way to Settings (if they said no before; iOS only asks once).
/// "Not now" hides it for two weeks; turning them on, or saying no to Apple's question, hides it
/// for good.
struct NotificationPromptCard: View {
    @Environment(\.modelContext) private var context
    @AppStorage("notifications.prompt.snoozedUntil") private var snoozedUntil: Double = 0
    /// They said no to Apple's question from this card: never shown again (Settings still has it).
    @AppStorage("notifications.prompt.declined") private var declined = false
    @State private var status: UNAuthorizationStatus?

    static let snoozeDays = 14

    private var visible: Bool {
        guard !declined, let status, status == .notDetermined || status == .denied else { return false }
        return Date().timeIntervalSince1970 >= snoozedUntil
    }

    var body: some View {
        Group {
            if visible {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    HStack(spacing: KXSpacing.sm) {
                        Image(systemName: "bell.badge.fill").font(.title3).foregroundStyle(KXColor.accent).accessibilityHidden(true)
                        Text("Turn on notifications").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    }
                    Text("Your day's training each morning, your results and new bests, a nudge when recovery is low, and your week in review. Never more than three a day, and you choose which in Settings.")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: KXSpacing.sm) {
                        Button("Not now") {
                            snoozedUntil = Date().addingTimeInterval(Double(Self.snoozeDays) * 86_400).timeIntervalSince1970
                        }
                        .buttonStyle(.kx(.secondary))
                        .accessibilityIdentifier("notifications.prompt.later")
                        Button(status == .denied ? "Open Settings" : "Turn on") { turnOn() }
                            .buttonStyle(.kx(.primary, fullWidth: true))
                            .accessibilityIdentifier("notifications.prompt.turnOn")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .kxCard()
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func turnOn() {
        if status == .denied {
            // iOS won't ask twice: their answer can only be changed in Settings.
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        Task {
            await NotificationService.requestPermissionIfNeeded()
            await NotificationService.scheduleMornings(in: context)
            await refresh()
            if status == .denied { declined = true }
        }
    }
}
