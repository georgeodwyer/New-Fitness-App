import SwiftUI
import SwiftData
import TrainingEngine

/// Progress, split four ways: Summary (this week, recovery over 30 days, daily exertion and
/// this week against usual), Running (totals, weekly distance, best efforts, every run),
/// Strength (weekly volume, lifts, every session) and Health (body data from Apple Health).
struct ProgressScreen: View {
    enum Section: String, CaseIterable, Identifiable {
        case summary = "Summary", running = "Running", strength = "Strength", health = "Health"
        var id: String { rawValue }
    }

    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query private var runs: [RunLogModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }) private var workouts: [StrengthLogModel]
    @State private var integrations = IntegrationSettings.shared
    @AppStorage("progress.section") private var sectionRaw = Section.summary.rawValue

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }
    private var section: Binding<Section> {
        Binding(get: { Section(rawValue: sectionRaw) ?? .summary }, set: { sectionRaw = $0.rawValue })
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
                    case .summary:
                        ProgressSummaryView(units: units, runs: runs, workouts: workouts, profile: profiles.first?.profile) {
                            sectionRaw = $0.rawValue
                        }
                    case .running: RunningProgressView(units: units)
                    case .strength: StrengthProgressView(units: units)
                    case .health: HealthProgressView()
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
        }
    }
}
