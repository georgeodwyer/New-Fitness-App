import SwiftUI
import SwiftData
import TrainingEngine

/// Settings: audio coaching, training profile (with plan regeneration), units,
/// integrations, account (export and delete) and about.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<CoachingSettingsModel> { $0.deletedAt == nil }) private var coachingSettings: [CoachingSettingsModel]
    @AppStorage(DeveloperSettings.simulateGPSKey) private var simulateGPS = false
    @AppStorage(DeveloperSettings.simulationSpeedKey) private var simulationSpeed = 10.0
    @AppStorage(AppearanceChoice.storageKey) private var appearance = AppearanceChoice.defaultChoice.rawValue
    @AppStorage(UnitPreference.key) private var storedUnits = UnitPreference.defaultForRegion.rawValue
    @Environment(AppRouter.self) private var router

    @State private var confirmRegenerate = false
    @State private var showWalkthrough = false
    @State private var confirmDelete = false
    @State private var confirmDeleteFinal = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var profileModel: UserProfileModel? { profiles.first }

    var body: some View {
        NavigationStack {
            List {
                // Profile card and the look of the app.
                Section {
                    profileCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    Picker("Appearance", selection: $appearance) {
                        Text("Dark").tag(AppearanceChoice.dark.rawValue)
                        Text("Light").tag(AppearanceChoice.light.rawValue)
                        Text("Match iPhone").tag(AppearanceChoice.system.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text("Appearance")
                }

                // Training: what the plan is built from.
                Section {
                    if let profileModel {
                        NavigationLink {
                            TrainingProfileView(profileModel: profileModel)
                        } label: {
                            settingsRow("Training profile", detail: trainingSummary(profileModel.profile),
                                        symbol: "figure.mixed.cardio", tint: KXColor.lift)
                        }
                        .accessibilityIdentifier("settings.training")
                    } else {
                        Button {
                            router.selectedTab = .plan
                        } label: {
                            settingsRow("Build a training plan", detail: "Running and lifting around your goal",
                                        symbol: "figure.mixed.cardio", tint: KXColor.lift)
                        }
                        .accessibilityIdentifier("settings.buildPlan")
                    }
                    Picker(selection: unitsBinding) {
                        Text("Kilometres & kg").tag(UnitSystem.metric)
                        Text("Miles & lb").tag(UnitSystem.imperial)
                    } label: {
                        settingsRow("Units", detail: nil, symbol: "ruler", tint: KXColor.slate)
                    }
                    if profileModel != nil {
                        Button {
                            confirmRegenerate = true
                        } label: {
                            Label("Regenerate my plan", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("Training")
                }

                // Coaching & watch: what you hear and feel during and around a session.
                Section("Coaching & watch") {
                    if let settings = coachingSettings.first {
                        NavigationLink {
                            CoachingSettingsView(settings: settings, units: currentUnits)
                        } label: {
                            settingsRow("Audio coaching", detail: coachingSummary(settings, units: currentUnits),
                                        symbol: "headphones", tint: KXColor.run)
                        }
                        .accessibilityIdentifier("settings.coaching")
                    }
                    AppleWatchRow()
                    GarminRow()
                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        settingsRow("Notifications", detail: "Morning summary and rest alerts", symbol: "bell.fill", tint: KXColor.warning)
                    }
                    .accessibilityIdentifier("settings.notifications")
                }

                Section("Connections") {
                    IntegrationsSection(includeWatch: false)
                }

                Section {
                    AccountSection()
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
                    Text("Account")
                } footer: {
                    Text("Deleting is permanent, here and in the cloud.")
                }

                Section {
                    Button {
                        showWalkthrough = true
                    } label: {
                        Label("App tour", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings.appTour")
                    NavigationLink {
                        HealthDisclaimerView()
                    } label: {
                        Label("Health & safety", systemImage: "cross.case")
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }
                    LabeledContent("Version", value: Bundle.main.appVersion)
                } header: {
                    Text("About")
                } footer: {
                    HStack(spacing: KXSpacing.sm) {
                        KXLogo(size: 28)
                        KXWordmark(height: 13)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, KXSpacing.lg)
                }

                // Testing tools: Xcode and TestFlight builds only, never the App Store.
                if BuildChannel.isTesting {
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
                }

                #if DEBUG
                Section("Developer") {
                    NavigationLink("Design system") { DesignGalleryView() }
                    Button("Add sample training history") { SampleData.seedHistory(into: context) }
                }
                #endif
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(KXColor.background.ignoresSafeArea())
            .tint(KXColor.accent)
            .fullScreenCover(isPresented: $showWalkthrough) {
                WalkthroughView { openToday in
                    showWalkthrough = false
                    if openToday { router.selectedTab = .today }
                }
            }
            .confirmationDialog("Rebuild your plan from your current answers?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
                Button("Keep my progress, rebuild from today") {
                    if let profile = profileModel?.profile { PlanService.rebuildRemainder(for: profile, in: context) }
                }
                Button("Start over from week 1") {
                    if let profile = profileModel?.profile { PlanService.createPlan(for: profile, in: context) }
                }
            } message: {
                Text("Keep my progress: you stay in the same week of the plan and today's and later sessions are rebuilt. Start over: a new plan from week 1. Either way, sessions you've done, records and progress are kept.")
            }
            .confirmationDialog("Delete your account and all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Continue", role: .destructive) { confirmDeleteFinal = true }
            } message: {
                Text("This removes your profile, plan, runs, workouts, records and settings. Consider exporting your data first.")
            }
            .alert("Delete everything permanently?", isPresented: $confirmDeleteFinal) {
                Button("Delete", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(AuthService.shared.isSignedIn
                     ? "Your account, everything backed up in the cloud and everything on this iPhone will be deleted. This can't be undone."
                     : "This can't be undone.")
            }
            .alert("Something went wrong", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private func settingsRow(_ title: String, detail: String?, symbol: String, tint: Color) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(KXColor.ink)
                if let detail { Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary) }
            }
        }
    }

    private func coachingSummary(_ settings: CoachingSettingsModel, units: UnitSystem) -> String {
        guard settings.paceCuesEnabled else { return "Pace cues off" }
        return "Cue after \(Int(settings.paceCueDelaySeconds)) s · ±\(CoachingSettingsView.toleranceText(settings.paceToleranceSecondsPerKm, units: units))"
    }

    /// Initials (from the account email) or the logo letter, the goal and the training summary.
    /// Tap to change the training profile.
    @ViewBuilder private var profileCard: some View {
        let email = AuthService.shared.email
        let initials = email.flatMap { $0.first.map { String($0).uppercased() } } ?? "K"
        let content = HStack(spacing: KXSpacing.md) {
            Text(initials)
                .font(KXFont.number(24, relativeTo: .title2))
                .foregroundStyle(KXColor.onAccent)
                .frame(width: 54, height: 54)
                .background(KXColor.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(profileModel.map { $0.profile.goal.displayName } ?? "No plan yet")
                    .font(KXFont.custom(.condensedBold, 22, relativeTo: .title3))
                    .textCase(.uppercase)
                    .foregroundStyle(KXColor.ink)
                Text(profileModel.map { trainingSummary($0.profile) } ?? "Build a plan around your goal")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
                if let email {
                    Text(email).font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: KXSpacing.sm)
            Text(profileModel == nil ? "Start" : "Edit")
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.ink)
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, KXSpacing.xs)
                .background(KXColor.surfaceTint, in: Capsule())
        }
        .kxCard()
        if let profileModel {
            NavigationLink { TrainingProfileView(profileModel: profileModel) } label: { content }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.profileCard")
        } else {
            Button { router.selectedTab = .plan } label: { content }
                .buttonStyle(.plain)
        }
    }

    private func trainingSummary(_ profile: AthleteProfile) -> String {
        "\(profile.goal.displayName) · \(profile.trainingDays.count) days · \(profile.equipment.displayName)"
    }

    private var currentUnits: UnitSystem {
        profileModel?.units ?? UnitSystem(rawValue: storedUnits) ?? UnitPreference.defaultForRegion
    }

    /// Units live in the profile once there is one; before that, in a per-phone preference.
    private var unitsBinding: Binding<UnitSystem> {
        Binding(
            get: { currentUnits },
            set: { units in
                storedUnits = units.rawValue
                if let profile = profileModel { AccountService.changeUnits(to: units, profile: profile, in: context) }
            }
        )
    }

    private func deleteAccount() async {
        if AuthService.shared.isSignedIn {
            do {
                try await AuthService.shared.deleteAccount()
            } catch {
                exportError = "Couldn't delete your cloud account: \(error.localizedDescription) Nothing has been deleted. Please try again when you're online."
                return
            }
        }
        AccountService.deleteEverything(in: context)
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
