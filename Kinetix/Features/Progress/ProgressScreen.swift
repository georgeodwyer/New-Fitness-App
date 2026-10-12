import SwiftUI
import SwiftData
import TrainingEngine

/// Progress: lifts (working weights, records, history), recent runs and sessions, and the load trend.
struct ProgressScreen: View {
    @Query(sort: \ExerciseStateModel.exerciseName) private var states: [ExerciseStateModel]
    @Query private var records: [PersonalRecordModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }, sort: \StrengthLogModel.startedAt, order: .reverse)
    private var workouts: [StrengthLogModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query private var runs: [RunLogModel]
    @State private var integrations = IntegrationSettings.shared

    private var finishedRuns: [RunLogModel] {
        runs.filter { $0.isFinished && !$0.isSoftDeleted }.sorted { $0.startedAt > $1.startedAt }
    }

    private var format: DisplayFormat { DisplayFormat(units: profiles.first?.units ?? .metric) }

    /// One row per exercise (main role preferred), only for exercises that have been trained.
    private var trainedLifts: [ExerciseStateModel] {
        let trained = Set(records.map(\.recordKey))
        var seen = Set<String>()
        return states
            .filter { !$0.isSoftDeleted && trained.contains($0.exerciseId) }
            .sorted { lhs, rhs in lhs.progressionKey.hasSuffix(".main") && !rhs.progressionKey.hasSuffix(".main") }
            .filter { seen.insert($0.exerciseId).inserted }
            .sorted { $0.exerciseName < $1.exerciseName }
    }

    private func best(_ kind: RecordKind, for exerciseId: String) -> Double? {
        records.first { $0.recordKey == exerciseId && $0.kindRaw == kind.rawValue && !$0.isSoftDeleted }?.value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Progress")
                    liftsSection
                    recentRuns
                    recentWorkouts
                    LoadTrendCard(report: LoadModel.report(
                        entries: DashboardService.loadEntries(runs: runs, lifts: workouts,
                                                              external: integrations.healthEnabled ? integrations.externalWorkouts : []),
                        today: .now, calendar: .kinetix))
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationDestination(for: ExerciseStateModel.self) { state in
                ExerciseHistoryView(exerciseId: state.exerciseId, name: state.exerciseName)
            }
        }
    }

    private var liftsSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Lifts", subtitle: "Working weight and best estimated 1-rep max")
            if trainedLifts.isEmpty {
                KXEmptyState(symbol: "dumbbell", title: "No lifts yet",
                             message: "Finish a strength session to see your working weights, records and progress here.")
            }
            ForEach(trainedLifts) { state in
                NavigationLink(value: state) {
                    HStack {
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(state.exerciseName).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                            Text("Working \(format.weight(state.workingWeightKg))")
                                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        Spacer()
                        if let e1rm = best(.estimatedOneRepMax, for: state.exerciseId) {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(format.weight(e1rm)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.accent)
                                Text("est. 1RM").font(.caption2).foregroundStyle(KXColor.inkSecondary)
                            }
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, KXSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("progress.lift")
            }
        }
        .kxCard()
    }

    private var recentWorkouts: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Recent strength sessions")
            if workouts.isEmpty {
                KXEmptyState(symbol: "list.bullet.rectangle", title: "No strength sessions yet",
                             message: "Completed sessions appear here with their total volume.")
            }
            ForEach(workouts.prefix(5)) { workout in
                HStack {
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(workout.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text(workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    Text(format.weight(workout.volumeKg)).font(KXFont.callout.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }

    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Recent runs")
            if finishedRuns.isEmpty {
                KXEmptyState(symbol: "figure.run", title: "No runs yet",
                             message: "Your runs appear here with distance, pace and heart rate.")
            }
            ForEach(finishedRuns.prefix(5)) { run in
                HStack {
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(run.title.isEmpty ? "Run" : run.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text(runDetail(run)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    Text(format.distance(run.distanceMeters, decimals: 2))
                        .font(KXFont.callout.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                    if let id = run.stravaActivityId, let url = URL(string: "https://www.strava.com/activities/\(id)") {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(StravaView.brand)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("View on Strava")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .kxCard()
    }

    private func runDetail(_ run: RunLogModel) -> String {
        var parts = [run.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month())]
        if let pace = run.averagePace { parts.append(format.pace(pace)) }
        if let hr = run.averageHeartRate { parts.append("\(Int(hr)) bpm") }
        return parts.joined(separator: " · ")
    }
}
