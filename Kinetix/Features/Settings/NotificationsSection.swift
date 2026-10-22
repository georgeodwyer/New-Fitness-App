import SwiftUI
import SwiftData
import UserNotifications

/// Settings for the morning summary and the gym rest alert.
struct NotificationsSection: View {
    @Environment(\.modelContext) private var context
    @AppStorage(NotificationService.Keys.morningEnabled) private var morningEnabled = true
    @AppStorage(NotificationService.Keys.morningMinutes) private var morningMinutes = 7 * 60
    @AppStorage(NotificationService.Keys.restEnabled) private var restEnabled = true
    @State private var isDenied = false

    var body: some View {
        Section {
            Toggle("Morning summary", isOn: $morningEnabled)
            if morningEnabled {
                DatePicker("Time", selection: morningTime, displayedComponents: .hourAndMinute)
            }
            Toggle("Rest timer alerts", isOn: $restEnabled)
            if isDenied {
                Button("Turn on notifications in Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("The morning summary tells you what's planned today. Rest alerts tell you when your rest is up if your phone is locked.")
        }
        .task { await refreshStatus() }
        .onChange(of: morningEnabled) { _, on in reschedule(asking: on) }
        .onChange(of: morningMinutes) { _, _ in reschedule(asking: false) }
        .onChange(of: restEnabled) { _, on in
            if on { Task { await NotificationService.requestPermissionIfNeeded(); await refreshStatus() } }
            else { NotificationService.cancelRest() }
        }
    }

    private var morningTime: Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: morningMinutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            morningMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
        }
    }

    private func reschedule(asking: Bool) {
        Task {
            if asking { await NotificationService.requestPermissionIfNeeded() }
            await NotificationService.scheduleMornings(in: context)
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        isDenied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
