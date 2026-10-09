import SwiftUI
import SwiftData
import TrainingEngine

/// Settings: audio coaching, training profile (with plan regeneration), units,
/// integrations, account (export and delete) and about.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfileModel]
    @Query private var coachingSettings: [CoachingSettingsModel]
    @AppStorage(DeveloperSettings.simulateGPSKey) private var simulateGPS = false
    @AppStorage(DeveloperSettings.simulationSpeedKey) private var simulationSpeed = 10.0

    @State private var confirmRegenerate = false
    @State private var confirmDelete = false
    @State private var confirmDeleteFinal = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var profileModel: UserProfileModel? { profiles.first }

    var body: some View {
        NavigationStack {
            List {
                if let settings = coachingSettings.first, let profile = profileModel?.profile {
                    Section("Coaching") {
                        NavigationLink {
                            CoachingSettingsView(settings: settings, units: profile.units)
                        } label: {
                            settingsRow("Audio coaching", detail: coachingSummary(settings, units: profile.units),
                                        symbol: "headphones", tint: KXColor.run)
                        }
                        .accessibilityIdentifier("settings.coaching")
                    }
                }

                if let profileModel {
                    Section {
                        NavigationLink {
                            TrainingProfileView(profileModel: profileModel)
                        } label: {
                            settingsRow("Training profile", detail: trainingSummary(profileModel.profile),
                                        symbol: "figure.mixed.cardio", tint: KXColor.lift)
                        }
                        .accessibilityIdentifier("settings.training")
                        Button {
                            confirmRegenerate = true
                        } label: {
                            Label("Regenerate my plan", systemImage: "arrow.clockwise")
                        }
                    } header: {
                        Text("Training")
                    } footer: {
                        Text("Changing your goal, days or equipment offers to rebuild your plan. Completed sessions and progress are always kept.")
                    }

                    Section("Units") {
                        Picker("Units", selection: unitsBinding(for: profileModel)) {
                            Text("Kilometres & kg").tag(UnitSystem.metric)
                            Text("Miles & lb").tag(UnitSystem.imperial)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    comingSoonRow("Apple Health", detail: "Heart rate, workouts and saving your sessions", symbol: "heart.fill")
                    comingSoonRow("Heart rate monitor", detail: "Bluetooth chest straps and Apple Watch", symbol: "waveform.path.ecg")
                    comingSoonRow("Strava", detail: "Upload runs automatically", symbol: "arrow.up.forward.app")
                } header: {
                    Text("Integrations")
                } footer: {
                    Text("These connect in a coming update.")
                }

                Section {
                    comingSoonRow("Account", detail: "Sign in with Apple or email to back up and sync", symbol: "person.crop.circle")
                    Button {
                        prepareExport()
                    } label: {
                        Label("Export my data", systemImage: "square.and.arrow.up")
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share export file (\(exportURL.lastPathComponent))", systemImage: "doc.text")
                        }
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete account and data", systemImage: "trash")
                    }
                } header: {
                    Text("Account & data")
                } footer: {
                    Text("Export gives you everything Kinetix stores about you as a JSON file. Deleting removes it all from this iPhone permanently.")
                }

                Section("About") {
                    NavigationLink {
                        HealthDisclaimerView()
                    } label: {
                        Label("Health & safety", systemImage: "cross.case")
                    }
                    LabeledContent("Version", value: Bundle.main.appVersion)
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
                    Text("Runs use a virtual runner looping Hyde Park instead of your GPS, including some off-pace moments so you can hear the coaching. Useful indoors.")
                }

                #if DEBUG
                Section("Developer") {
                    NavigationLink("Design system") { DesignGalleryView() }
                    Button("Add sample training history") { SampleData.seedHistory(into: context) }
                }
                #endif
            }
            .navigationTitle("Settings")
            .tint(KXColor.accent)
            .confirmationDialog("Rebuild your plan from your current answers?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                Button("Regenerate plan") {
                    if let profile = profileModel?.profile { PlanService.createPlan(for: profile, in: context) }
                }
            } message: {
                Text("Upcoming sessions are replaced. Completed sessions, records and progress are kept.")
            }
            .confirmationDialog("Delete your account and all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Continue", role: .destructive) { confirmDeleteFinal = true }
            } message: {
                Text("This removes your profile, plan, runs, workouts, records and settings. Consider exporting your data first.")
            }
            .alert("Delete everything permanently?", isPresented: $confirmDeleteFinal) {
                Button("Delete", role: .destructive) { AccountService.deleteEverything(in: context) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private func settingsRow(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
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
        }
    }

    private func comingSoonRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(KXColor.ink)
                    Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            } icon: {
                Image(systemName: symbol).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            KXChip(text: "Soon", variant: .outlined)
        }
        .accessibilityElement(children: .combine)
    }

    private func coachingSummary(_ settings: CoachingSettingsModel, units: UnitSystem) -> String {
        guard settings.paceCuesEnabled else { return "Pace cues off" }
        return "Cue after \(Int(settings.paceCueDelaySeconds)) s · ±\(CoachingSettingsView.toleranceText(settings.paceToleranceSecondsPerKm, units: units))"
    }

    private func trainingSummary(_ profile: AthleteProfile) -> String {
        "\(profile.goal.displayName) · \(profile.trainingDays.count) days · \(profile.equipment.displayName)"
    }

    private func unitsBinding(for profile: UserProfileModel) -> Binding<UnitSystem> {
        Binding(
            get: { profile.units },
            set: { AccountService.changeUnits(to: $0, profile: profile, in: context) }
        )
    }

    private func prepareExport() {
        do {
            exportURL = try AccountService.writeExportFile(in: context)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

extension Equipment {
    var displayName: String {
        switch self {
        case .fullGym: return "Full gym"
        case .homeGym: return "Home gym"
        case .dumbbellsOnly: return "Dumbbells"
        case .bodyweight: return "Bodyweight"
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
