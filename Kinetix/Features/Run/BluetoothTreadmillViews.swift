import SwiftUI
import TrainingEngine

/// Before a treadmill run: find and pair a Bluetooth treadmill, and choose whether Kinetix sets
/// the speed.
struct TreadmillConnectionView: View {
    @State private var monitor = TreadmillMonitor.shared
    @State private var settings = IntegrationSettings.shared
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(spacing: KXSpacing.sm) {
                Image(systemName: monitor.isConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(monitor.isConnected ? KXColor.success : KXColor.inkSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(settings.treadmillID == nil ? "Find" : "Change") { choosing = true }
                    .buttonStyle(.kx(.outlined))
                    .accessibilityIdentifier("treadmill.find")
            }
            if monitor.isConnected {
                if monitor.canControl {
                    Toggle("Kinetix sets the speed", isOn: Binding(get: { settings.treadmillControl },
                                                                   set: { settings.treadmillControl = $0 }))
                        .font(KXFont.bodyEmphasis)
                        .tint(KXColor.accent)
                        .accessibilityIdentifier("treadmill.control")
                    Text(settings.treadmillControl
                         ? "Before each speed change you hear a 3-second countdown. It's never faster than your target pace range. Pause stops the belt, and so does the treadmill's own stop key."
                         : "You set the speed: Kinetix says the speed for each step.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This treadmill doesn't let apps set its speed: Kinetix says the speed for each step and reads distance from the belt.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { monitor.connectToSaved() }
        .sheet(isPresented: $choosing) {
            TreadmillPickerSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private var title: String {
        switch monitor.state {
        case .connected(let name): return name
        case .connecting(let name): return "Connecting to \(name)…"
        case .off: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth isn't allowed"
        case .unsupported: return "Bluetooth isn't available"
        default: return settings.treadmillName ?? "No treadmill yet"
        }
    }

    private var detail: String {
        if let reading = monitor.reading, let speed = reading.speedKmh {
            return "Belt \(String(format: "%.1f", speed)) km/h" + (reading.inclinePercent.map { " · incline \(String(format: "%.1f", $0))%" } ?? "")
        }
        if case .unauthorized = monitor.state { return "Allow Bluetooth for Kinetix in the Settings app." }
        return settings.treadmillID == nil
            ? "Turn the treadmill on, then tap Find. Distance and speed come from the belt."
            : "Turn the treadmill on. Distance and speed come from the belt."
    }
}

/// Treadmills nearby that speak the standard Bluetooth fitness-machine language.
struct TreadmillPickerSheet: View {
    @State private var monitor = TreadmillMonitor.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if monitor.discovered.isEmpty {
                        HStack(spacing: KXSpacing.sm) {
                            ProgressView()
                            Text("Looking for treadmills…").foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                    ForEach(monitor.discovered) { device in
                        Button {
                            monitor.pair(device)
                            dismiss()
                        } label: {
                            HStack {
                                Label(device.name, systemImage: "figure.run.treadmill")
                                Spacer()
                                if IntegrationSettings.shared.treadmillID == device.id {
                                    Image(systemName: "checkmark").foregroundStyle(KXColor.accent)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Turn the treadmill on (some need the belt started once or their Bluetooth turned on in their menu). Only treadmills using the standard Bluetooth fitness-machine service (FTMS) appear. If yours doesn't, use Speed I set or Steps instead.")
                }
                if IntegrationSettings.shared.treadmillID != nil {
                    Section {
                        Button("Forget this treadmill", role: .destructive) {
                            monitor.forget()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Your treadmill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { monitor.startScan() }
            .onDisappear { monitor.stopScan() }
        }
    }
}

/// During a Bluetooth treadmill run: the belt's speed and incline, the speed for this step,
/// the countdown to a change, − / + and a big Stop belt.
struct BluetoothTreadmillCard: View {
    let model: RunWorkoutModel
    @State private var monitor = TreadmillMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                KXOverline(monitor.isConnected ? "Treadmill · Bluetooth" : "Treadmill · reconnecting…")
                Spacer()
                if let target = model.beltTargetKmh {
                    Text((model.controlsTreadmill ? "Kinetix sets " : "Set to ") + TreadmillSpeed.text(kilometresPerHour: target, units: model.units))
                        .font(KXFont.captionEmphasis).foregroundStyle(KXColor.accent)
                }
            }
            HStack(spacing: KXSpacing.md) {
                if model.controlsTreadmill {
                    KXIconButton(systemImage: "minus", accessibilityLabel: "Slower", variant: .neutral, size: 44) { model.nudgeBelt(by: -0.1) }
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(monitor.reading?.speedKmh.map { TreadmillSpeed.text(kilometresPerHour: $0, units: model.units) } ?? "–")
                        .font(KXFont.number(34, relativeTo: .title))
                        .foregroundStyle(KXColor.ink)
                    if let incline = monitor.reading?.inclinePercent {
                        Text("Incline \(String(format: "%.1f", incline))%").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
                if model.controlsTreadmill {
                    KXIconButton(systemImage: "plus", accessibilityLabel: "Faster", variant: .neutral, size: 44) { model.nudgeBelt(by: 0.1) }
                }
            }
            if let count = model.speedChangeCountdown {
                Label("New speed in \(count)…", systemImage: "timer")
                    .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.accent)
                    .accessibilityLabel("Speed changes in \(count) seconds")
            }
            if let problem = monitor.controlProblem {
                Text(problem).font(KXFont.caption).foregroundStyle(KXColor.warning)
            }
            if model.controlsTreadmill {
                Button(role: .destructive) { model.stopBelt() } label: {
                    Label("Stop belt", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
                .accessibilityIdentifier("treadmill.stopBelt")
            } else {
                Text("Distance and speed come from the belt.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .kxCard(.tinted)
    }
}
