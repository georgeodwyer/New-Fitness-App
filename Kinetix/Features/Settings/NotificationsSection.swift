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
    @AppStorage(TrainingNotifications.Keys.sessionEnabled) private var sessionEnabled = true
    @AppStorage(TrainingNotifications.Keys.sessionLead) private var sessionLead = 60
    @AppStorage(TrainingNotifications.Keys.morningSessionMinutes) private var morningSessionMinutes = 7 * 60
    @AppStorage(TrainingNotifications.Keys.eveningSessionMinutes) private var eveningSessionMinutes = 18 * 60
    @AppStorage(TrainingNotifications.Keys.bedtimeEnabled) private var bedtimeEnabled = false
    @AppStorage(TrainingNotifications.Keys.sleepNeedMinutes) private var sleepNeedMinutes = 8 * 60
    @AppStorage(TrainingNotifications.Keys.fuellingEnabled) private var fuellingEnabled = true
    @AppStorage(TrainingNotifications.Keys.checkInEnabled) private var checkInEnabled = true
    @AppStorage(TrainingNotifications.Keys.weeklyEnabled) private var weeklyEnabled = true

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

        Section {
            Toggle("Session reminder", isOn: $sessionEnabled)
            if sessionEnabled {
                Picker("Remind me", selection: $sessionLead) {
                    Text("30 min before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("2 hours before").tag(120)
                }
                DatePicker("Morning sessions at", selection: minutesBinding($morningSessionMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Evening sessions at", selection: minutesBinding($eveningSessionMinutes), displayedComponents: .hourAndMinute)
            }
            Toggle("Fuelling tips", isOn: $fuellingEnabled)
            Toggle("Check-in reminder", isOn: $checkInEnabled)
            Toggle("Sunday week review", isOn: $weeklyEnabled)
        } header: {
            Text("Training")
        } footer: {
            Text("Fuelling tips: carbs the evening before a long run or race, fuel on runs over 75 minutes, protein after the gym. The check-in reminder comes at 10:00 if you haven't done it. General guidance, not medical advice.")
        }

        Section {
            Toggle("Bedtime reminder", isOn: $bedtimeEnabled)
            if bedtimeEnabled {
                Stepper("Sleep need: \(formatHours(sleepNeedMinutes))", value: $sleepNeedMinutes, in: 6 * 60...10 * 60, step: 15)
            }
        } header: {
            Text("Sleep")
        } footer: {
            Text("A nudge to wind down 30 minutes before you should be asleep: enough sleep before tomorrow's first session, and 30 minutes more before a hard or long one.")
        }
        .onChange(of: trainingSettingsKey) { _, _ in reschedule(asking: true) }
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

    /// Changes whenever a training notification setting changes.
    private var trainingSettingsKey: String {
        [sessionEnabled, bedtimeEnabled, fuellingEnabled, checkInEnabled, weeklyEnabled].map { $0 ? "1" : "0" }.joined()
            + "\(sessionLead)-\(morningSessionMinutes)-\(eveningSessionMinutes)-\(sleepNeedMinutes)"
    }

    private func formatHours(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private func minutesBinding(_ value: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: value.wrappedValue, to: Calendar.current.startOfDay(for: .now)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            value.wrappedValue = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
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

/// Settings → Notifications.
struct NotificationsSettingsView: View {
    var body: some View {
        Form { NotificationsSection() }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
    }
}
