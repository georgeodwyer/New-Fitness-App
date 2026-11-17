import SwiftUI
import SwiftData
import TrainingEngine

/// The Profile tab: who you are and what you've done (profile card, badges, race predictions,
/// best efforts, strength records), running tools, and Settings behind the cog.
struct ProfileView: View {
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<PersonalRecordModel> { $0.deletedAt == nil }, sort: \PersonalRecordModel.achievedAt, order: .reverse)
    private var records: [PersonalRecordModel]
    @AppStorage(UnitPreference.key) private var storedUnits = UnitPreference.defaultForRegion.rawValue
    @Environment(AppRouter.self) private var router

    private var profileModel: UserProfileModel? { profiles.first }
    private var units: UnitSystem {
        profileModel?.units ?? UnitSystem(rawValue: storedUnits) ?? UnitPreference.defaultForRegion
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    profileCard
                    AchievementsCard()
                    if let profile = profileModel?.profile { RacePredictionsCard(profile: profile) }
                    BestEffortsCard(units: units)
                    let lifts = records.filter { $0.kindRaw == RecordKind.estimatedOneRepMax.rawValue }
                    if !lifts.isEmpty { RecentRecordsCard(records: Array(lifts.prefix(5)), units: units) }
                    toolsCard
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("profile.settings")
                }
            }
        }
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
                Text(profileModel.map { summary($0.profile) } ?? "Build a plan around your goal")
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
                .accessibilityIdentifier("profile.profileCard")
        } else {
            Button { router.selectedTab = .plan } label: { content }
                .buttonStyle(.plain)
        }
    }

    private func summary(_ profile: AthleteProfile) -> String {
        "\(profile.runningExperience.displayName) runner · \(profile.trainingDays.count) days · \(profile.equipment.displayName)"
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Tools", subtitle: "Handy calculators for runners")
            NavigationLink { PaceCalculatorView(units: units) } label: {
                toolRow("Pace calculator", detail: "Pace, time and distance: enter two, get the third", symbol: "speedometer")
            }
            .accessibilityIdentifier("tools.pace")
            Divider().overlay(KXColor.border)
            NavigationLink { SplitPlannerView(units: units) } label: {
                toolRow("Split planner", detail: "Even or negative splits for a goal time", symbol: "flag.checkered")
            }
            .accessibilityIdentifier("tools.splits")
            Divider().overlay(KXColor.border)
            NavigationLink { ConverterView(units: units) } label: {
                toolRow("Treadmill & unit converter", detail: "Pace ↔ treadmill speed, km ↔ miles", symbol: "arrow.left.arrow.right")
            }
            .accessibilityIdentifier("tools.converter")
        }
        .kxCard()
    }

    private func toolRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: symbol).foregroundStyle(KXColor.run).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
