import SwiftUI
import SwiftData

/// Settings → Apple Workout app: send planned runs to the Workout app on Apple Watch.
struct AppleWorkoutRow: View {
    @State private var service = AppleWorkoutService.shared

    var body: some View {
        if service.isSupported {
            NavigationLink {
                AppleWorkoutView()
            } label: {
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: "figure.run.circle.fill")
                        .foregroundStyle(KXColor.success)
                        .frame(width: 30, height: 30)
                        .background(KXColor.success.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Workout app").foregroundStyle(KXColor.ink)
                        Text(service.isEnabled ? "Planned runs sent to your watch" : "Run your plan in Apple's Workout app")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    if service.isEnabled {
                        KXChip(text: "On", systemImage: "checkmark", variant: .success)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("settings.appleWorkout")
        }
    }
}

struct AppleWorkoutView: View {
    @Environment(\.modelContext) private var context
    @State private var service = AppleWorkoutService.shared
    @State private var working = false

    var body: some View {
        List {
            Section {
                Text("Prefer Apple's own Workout app? Kinetix can put your planned runs for the next week in it, with each part's distance or time and your pace range. Open Workout on your watch and find them under Kinetix. Runs you do there come back through Apple Health and tick off your plan.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            Section {
                Toggle("Send planned runs", isOn: Binding(
                    get: { service.isEnabled },
                    set: { on in
                        working = true
                        Task {
                            if on { await service.enable(in: context) } else { await service.disable() }
                            working = false
                        }
                    }))
                    .disabled(working)
                    .accessibilityIdentifier("appleWorkout.toggle")
                if service.isEnabled {
                    Button {
                        working = true
                        Task {
                            await service.sync(in: context, force: true)
                            working = false
                        }
                    } label: {
                        Label("Send now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(working)
                }
            } footer: {
                if let message = service.message {
                    Text(message)
                } else if service.isEnabled, let sent = service.lastSentAt {
                    Text("Last sent \(sent.formatted(.relative(presentation: .named))). Updates by itself when your plan changes.")
                }
            }
        }
        .navigationTitle("Apple Workout app")
        .navigationBarTitleDisplayMode(.inline)
    }
}
