import SwiftUI
import SwiftData
import AuthenticationServices
import KinetixSync
import TrainingEngine

/// Settings → Integrations rows.
struct IntegrationsSection: View {
    @State private var settings = IntegrationSettings.shared
    @State private var health = HealthService.shared
    @State private var monitor = HeartRateMonitor.shared
    @State private var strava = StravaService.shared

    var body: some View {
        NavigationLink {
            AppleHealthView()
        } label: {
            IntegrationRow(title: "Apple Health", detail: healthDetail, symbol: "heart.fill", tint: Color(red: 1, green: 0.22, blue: 0.37),
                           connected: settings.healthEnabled)
        }
        .accessibilityIdentifier("settings.health")
        NavigationLink {
            HeartRateSensorView()
        } label: {
            IntegrationRow(title: "Heart rate strap", detail: settings.heartRateSensorName ?? "Pair a Bluetooth chest strap",
                           symbol: "waveform.path.ecg", tint: KXColor.danger, connected: settings.heartRateSensorID != nil)
        }
        .accessibilityIdentifier("settings.heartRate")
        NavigationLink {
            StravaView()
        } label: {
            IntegrationRow(title: "Strava", detail: stravaDetail, symbol: "arrow.up.forward.app", tint: StravaView.brand,
                           connected: strava.isConnected)
        }
        .accessibilityIdentifier("settings.strava")
    }

    private var healthDetail: String {
        guard health.isAvailable else { return "Not available on this device" }
        return settings.healthEnabled ? "Saving workouts · reading heart rate" : "Save workouts and read heart rate"
    }

    private var stravaDetail: String {
        switch strava.state {
        case .unavailable: return "Not set up in this build"
        case .disconnected: return "Upload runs automatically"
        case .connected(let name): return name.map { "Connected as \($0)" } ?? "Connected"
        }
    }
}

private struct IntegrationRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let connected: Bool

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(KXColor.ink)
                Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            if connected {
                KXChip(text: "On", systemImage: "checkmark", variant: .success)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Apple Health

struct AppleHealthView: View {
    @Environment(\.modelContext) private var context
    @State private var settings = IntegrationSettings.shared
    @State private var health = HealthService.shared
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                IntegrationHeader(symbol: "heart.fill", tint: Color(red: 1, green: 0.22, blue: 0.37), title: "Apple Health",
                                  text: "Save your runs (with route) and strength sessions to Health, use your Apple Watch heart rate during runs, and let resting heart rate and workouts from other apps inform your training load.")
            }
            .listRowBackground(Color.clear)

            if !health.isAvailable {
                Section { Text("Apple Health isn't available on this device.").foregroundStyle(KXColor.inkSecondary) }
            } else if !settings.healthEnabled {
                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        Label(working ? "Connecting…" : "Connect Apple Health", systemImage: "heart.text.square")
                    }
                    .disabled(working)
                    .accessibilityIdentifier("health.connect")
                } footer: {
                    Text("Apple asks which data to share. You can change this any time in the Health app: tap your profile, then Apps, then Kinetix.")
                }
            } else {
                Section("Today") {
                    if let signal = health.restingHeartRate {
                        LabeledContent("Resting heart rate", value: signal.description)
                        if signal.isElevated {
                            Label("Higher than usual. If you also feel run down, Kinetix eases today's plan.", systemImage: "exclamationmark.triangle.fill")
                                .font(KXFont.caption)
                                .foregroundStyle(KXColor.ink)
                                .symbolRenderingMode(.multicolor)
                        }
                    } else {
                        LabeledContent("Resting heart rate", value: "Not enough data yet")
                    }
                    LabeledContent("Other workouts (4 weeks)", value: "\(settings.externalWorkouts.count)")
                }
                Section {
                    Toggle("Apple Watch heart rate during runs", isOn: $settings.useWatchHeartRate)
                } footer: {
                    Text("Heart rate appears when your Watch is recording a workout (for example an Outdoor Run in the Workout app). A Bluetooth chest strap updates faster and is used first if both are connected.")
                }
                if !health.canSaveWorkouts {
                    Section {
                        Label("Saving workouts is turned off in Health. Turn on Workouts for Kinetix in the Health app to save your sessions.",
                              systemImage: "info.circle")
                            .font(KXFont.callout)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        settings.healthEnabled = false
                        settings.healthConnectedAt = nil
                        settings.externalWorkouts = []
                    } label: {
                        Label("Stop using Apple Health", systemImage: "xmark.circle")
                    }
                } footer: {
                    Text("Sessions you finish from now on are saved to Health automatically. Workouts already saved stay in Health.")
                }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .task { await health.refresh(force: true) }
        .alert("Couldn't connect", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func connect() async {
        working = true
        defer { working = false }
        do {
            try await health.requestAuthorization()
            settings.healthEnabled = true
            settings.healthConnectedAt = .now
            await health.refresh(force: true)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Heart rate strap

struct HeartRateSensorView: View {
    @State private var settings = IntegrationSettings.shared
    @State private var monitor = HeartRateMonitor.shared

    var body: some View {
        List {
            Section {
                IntegrationHeader(symbol: "waveform.path.ecg", tint: KXColor.danger, title: "Heart rate strap",
                                  text: "Pair a Bluetooth chest or arm strap (Polar, Garmin, Wahoo and most others) to see live heart rate during runs. Kinetix reconnects to it automatically when you start a run.")
            }
            .listRowBackground(Color.clear)

            if let message = problem {
                Section { Label(message, systemImage: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor) }
            }

            if let name = settings.heartRateSensorName {
                Section("Paired") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).foregroundStyle(KXColor.ink)
                            Text(connectionText).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        Spacer()
                        if let bpm = monitor.heartRate {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Image(systemName: "heart.fill").foregroundStyle(KXColor.danger).symbolEffect(.pulse)
                                Text("\(bpm)").font(KXFont.metricSmall).monospacedDigit()
                                Text("bpm").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Button("Forget this strap", role: .destructive) { monitor.forget() }
                }
            }

            Section {
                if monitor.state == .scanning {
                    HStack {
                        ProgressView()
                        Text("Looking for straps… Put yours on so it wakes up.").foregroundStyle(KXColor.inkSecondary)
                    }
                    ForEach(monitor.discovered.filter { $0.id != settings.heartRateSensorID }) { device in
                        Button {
                            monitor.pair(device)
                        } label: {
                            HStack {
                                Label(device.name, systemImage: "dot.radiowaves.left.and.right")
                                Spacer()
                                Text("Pair").foregroundStyle(KXColor.accent)
                            }
                        }
                        .foregroundStyle(KXColor.ink)
                    }
                    Button("Stop looking") { monitor.stopScan() }
                } else {
                    Button {
                        monitor.startScan()
                    } label: {
                        Label(settings.heartRateSensorID == nil ? "Find a strap" : "Pair a different strap", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("hr.scan")
                }
            } footer: {
                Text("Straps only show up while you're wearing them. If yours is connected to another app or a watch, disconnect it there first.")
            }
        }
        .navigationTitle("Heart rate strap")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .onAppear { monitor.connectToSaved() }
        .onDisappear {
            monitor.stopScan()
            monitor.disconnect()
        }
    }

    private var connectionText: String {
        switch monitor.state {
        case .connected: return "Connected"
        case .connecting: return "Connecting… (wear the strap to wake it)"
        default: return "Not connected"
        }
    }

    private var problem: String? {
        switch monitor.state {
        case .off: return "Bluetooth is off. Turn it on in Control Centre."
        case .unauthorized: return "Kinetix isn't allowed to use Bluetooth. Turn it on in the Settings app → Kinetix."
        case .unsupported: return "This device doesn't support Bluetooth heart rate straps."
        default: return nil
        }
    }
}

// MARK: - Strava

struct StravaView: View {
    /// Strava's brand orange.
    static let brand = Color(red: 252 / 255, green: 82 / 255, blue: 0)

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @State private var settings = IntegrationSettings.shared
    @State private var strava = StravaService.shared
    @State private var working = false
    @State private var errorText: String?
    @State private var confirmDisconnect = false

    var body: some View {
        List {
            Section {
                IntegrationHeader(symbol: "arrow.up.forward.app", tint: Self.brand, title: "Strava",
                                  text: "Upload your runs to Strava automatically when you finish them, with route, splits and heart rate. Strength sessions can go up too.")
            }
            .listRowBackground(Color.clear)

            switch strava.state {
            case .unavailable:
                Section {
                    Text("Strava hasn't been set up for this version of the app yet. (Developer: see docs/STRAVA.md.)")
                        .foregroundStyle(KXColor.inkSecondary)
                }
            case .disconnected:
                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        // Strava's brand rules ask for their official button artwork: add it to
                        // Assets as "StravaConnectButton" (docs/STRAVA.md). Until then, a plain version.
                        if UIImage(named: "StravaConnectButton") != nil && !working {
                            Image("StravaConnectButton").resizable().scaledToFit().frame(height: 48)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Connect with Strava")
                        } else {
                            Text(working ? "Connecting…" : "Connect with Strava")
                                .font(KXFont.bodyEmphasis)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Self.brand, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(working)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("strava.connect")
                } footer: {
                    Text("You'll sign in on Strava's website and choose what Kinetix may do. Only sessions you finish after connecting are uploaded.")
                }
            case .connected(let name):
                Section("Account") {
                    LabeledContent("Connected as", value: name ?? "Strava athlete")
                }
                Section {
                    Toggle("Upload runs", isOn: $settings.stravaUploadRuns)
                    Toggle("Upload strength sessions", isOn: $settings.stravaUploadLifts)
                } header: {
                    Text("Automatic uploads")
                } footer: {
                    Text("Runs recorded with simulated GPS are never uploaded. If you're offline, uploads are retried the next time you open Kinetix.")
                }
                if !settings.uploadFailures.isEmpty {
                    Section("Couldn't upload") {
                        ForEach(Array(Set(settings.uploadFailures.values)).sorted(), id: \.self) { message in
                            Text(message).font(KXFont.callout)
                        }
                        Button("Clear") { settings.uploadFailures = [:] }
                    }
                }
                Section {
                    Button("Disconnect Strava", role: .destructive) { confirmDisconnect = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if UIImage(named: "StravaCompatible") != nil {
                Image("StravaCompatible").resizable().scaledToFit().frame(height: 24)
                    .padding(.bottom, KXSpacing.md)
                    .accessibilityLabel("Compatible with Strava")
            }
        }
        .navigationTitle("Strava")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .confirmationDialog("Disconnect Strava?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await strava.disconnect() } }
        } message: {
            Text("New sessions won't be uploaded. Activities already on Strava stay there.")
        }
        .alert("Couldn't connect to Strava", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func connect() async {
        guard let url = strava.beginAuthorization() else { return }
        working = true
        defer { working = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: StravaConfig.callbackScheme,
                                                                          preferredBrowserSession: .ephemeral)
            try await strava.completeAuthorization(callback: callback)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the sheet.
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Icon, title and explanation at the top of each integration screen.
private struct IntegrationHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(tint, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text(title).font(KXFont.title).foregroundStyle(KXColor.ink)
            Text(text).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowInsets(EdgeInsets())
        .padding(.vertical, KXSpacing.sm)
    }
}
