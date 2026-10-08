import SwiftUI
import SwiftData
import TrainingEngine

/// Settings. Milestone 6 adds coaching, plan and account options.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfileModel]
    @State private var confirmReset = false

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
