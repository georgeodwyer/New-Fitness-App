import SwiftUI

/// Settings → Garmin: link a Garmin watch running the Kinetix app, send the plan, and how
/// runs come back.
struct GarminRow: View {
    @State private var garmin = GarminService.shared

    var body: some View {
        NavigationLink {
            GarminView()
        } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: "applewatch.side.right")
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(red: 0, green: 0.48, blue: 0.76), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Garmin").foregroundStyle(KXColor.ink)
                    Text(garmin.devices.isEmpty ? "Run your plan on a Garmin watch" : garmin.devices.map(\.name).joined(separator: ", "))
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
                if !garmin.devices.isEmpty {
                    KXChip(text: "On", systemImage: "checkmark", variant: .success)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("settings.garmin")
    }
}

struct GarminView: View {
    @State private var garmin = GarminService.shared

    var body: some View {
        List {
            Section {
                Text("Run your Kinetix sessions on a Garmin with step-by-step pace targets. Each run is saved to Garmin Connect as normal and comes back to Kinetix to tick off your plan.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            if !garmin.isAvailable {
                Section {
                    Label("This version of Kinetix doesn't include Garmin support yet.", systemImage: "exclamationmark.triangle")
                }
            } else if garmin.devices.isEmpty {
                Section {
                    Button {
                        garmin.connect()
                    } label: {
                        Label("Connect a Garmin watch", systemImage: "link")
                    }
                    .accessibilityIdentifier("garmin.connect")
                } footer: {
                    Text("Opens the Garmin Connect app to choose your watch, then comes back here. You need Garmin Connect on this iPhone and the Kinetix app on your watch.")
                }
            } else {
                Section("Your watches") {
                    ForEach(garmin.devices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).foregroundStyle(KXColor.ink)
                                Text(device.statusText).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                            }
                            Spacer()
                            Circle()
                                .fill(device.isReady ? KXColor.success : KXColor.inkTertiary)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    Button {
                        garmin.sendPlan(force: true)
                    } label: {
                        Label("Send this week's runs now", systemImage: "arrow.up.circle")
                    }
                    .accessibilityIdentifier("garmin.send")
                    if let sent = garmin.lastSentAt {
                        LabeledContent("Last sent", value: sent.formatted(.relative(presentation: .named)))
                    }
                    if let received = garmin.lastResultAt {
                        LabeledContent("Last run received", value: received.formatted(.relative(presentation: .named)))
                    }
                } footer: {
                    Text("Your runs for the next 7 days are sent whenever Kinetix opens and when your plan changes. Open the Kinetix app on your watch to pick them up.")
                }
                Section {
                    Button("Choose watches again") { garmin.connect() }
                    Button("Disconnect", role: .destructive) { garmin.forget() }
                }
            }
            Section("How it works") {
                step(1, "On your watch, open Kinetix and pick today's run. Press START.")
                step(2, "The watch buzzes at each step. Your pace shows green on target and amber off it.")
                step(3, "Press BACK (lap) to skip to the next step early. Press STOP to pause, then BACK to save.")
                step(4, "Saved runs go to Garmin Connect, and to Kinetix next time both apps are open.")
            }
            Section {
                Text("Kinetix doesn't upload Garmin runs to Strava or Apple Health itself: link those to Garmin Connect instead, so nothing is uploaded twice.")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
        }
        .navigationTitle("Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .onAppear { garmin.refreshStatus() }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Text("\(number)")
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.onAccent)
                .frame(width: 20, height: 20)
                .background(KXColor.accent, in: Circle())
                .accessibilityHidden(true)
            Text(text).font(KXFont.callout).foregroundStyle(KXColor.ink)
        }
    }
}
