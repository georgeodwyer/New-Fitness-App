import SwiftUI
import SwiftData
import TrainingEngine

/// Progress, split four ways: Running (totals, weekly distance, best efforts, every run),
/// Strength (weekly volume, lifts, every session), Overall (daily strain and this week against usual) and
/// Health (body data from Apple Health over 7 or 30 days).
struct ProgressScreen: View {
    enum Section: String, CaseIterable, Identifiable {
        case running = "Running", strength = "Strength", overall = "Overall", health = "Health"
        var id: String { rawValue }
    }

    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query private var runs: [RunLogModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }) private var workouts: [StrengthLogModel]
    @State private var integrations = IntegrationSettings.shared
    @AppStorage("progress.section") private var sectionRaw = Section.running.rawValue

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }
    private var section: Binding<Section> {
        Binding(get: { Section(rawValue: sectionRaw) ?? .running }, set: { sectionRaw = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Progress")
                    Picker("Section", selection: section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("progress.section")
                    switch section.wrappedValue {
                    case .running: RunningProgressView(units: units)
                    case .strength: StrengthProgressView(units: units)
                    case .overall: overall
                    case .health: HealthProgressView()
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
        }
    }

    private var overall: some View {
        let report = LoadModel.report(
            entries: DashboardService.loadEntries(runs: runs, lifts: workouts,
                                                  external: integrations.loadWorkouts),
            today: .now, calendar: .kinetix)
        let strain = StrainService.report(sessions: [], runs: runs, lifts: workouts, checkIn: nil, profile: profiles.first?.profile,
                                          external: integrations.loadWorkouts, health: HealthInputs.current)
        return VStack(alignment: .leading, spacing: KXSpacing.xl) {
            DailyStrainChart(days: strain.days)
            LoadTrendCard(report: report)
        }
    }
}
