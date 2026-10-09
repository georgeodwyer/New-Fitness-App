import SwiftUI
import SwiftData
import TrainingEngine

/// Settings. Milestone 6 adds coaching, plan and account options.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfileModel]
    @State private var confirmReset = false
    @AppStorage(DeveloperSettings.simulateGPSKey) private var simulateGPS = false
    @AppStorage(DeveloperSettings.simulationSpeedKey) private var simulationSpeed = 10.0

    var body: some View {
        NavigationStack {
            List {
                if let profile = profiles.first {
                    Section("Units") {
                        Picker("Units", selection: unitsBinding(for: profile)) {
                            Text("Kilometres & kg").tag(UnitSystem.metric)
                            Text("Miles & lb").tag(UnitSystem.imperial)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                if let profile = profiles.first {
                    Section {
                        Button("Regenerate my plan") { PlanService.createPlan(for: profile.profile, in: context) }
                    } footer: {
                        Text("Builds a fresh plan from your current answers. Completed sessions are kept.")
                    }
                }
                Section {
                    Toggle("Simulated GPS for runs", isOn: $simulateGPS)
                    if simulateGPS {
                        Picker("Simulation speed", selection: $simulationSpeed) {
                            Text("Real time").tag(1.0)
                            Text("5× faster").tag(5.0)
                            Text("10× faster").tag(10.0)
                            Text("30× faster").tag(30.0)
                        }
                    }
                } header: {
                    Text("Testing")
                } footer: {
                    Text("Runs use a virtual runner looping Hyde Park instead of your GPS, including some off-pace moments so you can hear the coaching. Useful in the simulator or indoors.")
                }
                Section("Developer") {
                    NavigationLink("Design system") { DesignGalleryView() }
                    Button("Reset all data", role: .destructive) { confirmReset = true }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Erase everything on this device?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) { SampleData.eraseAll(in: context) }
            }
        }
    }

    private func unitsBinding(for profile: UserProfileModel) -> Binding<UnitSystem> {
        Binding(
            get: { profile.units },
            set: { newValue in
                var updated = profile.profile
                updated.units = newValue
                profile.profile = updated
                try? context.save()
            }
        )
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
