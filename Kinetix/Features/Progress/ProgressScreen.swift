import SwiftUI
import SwiftData
import TrainingEngine

/// Progress: lifts (working weights, records, history). Training load arrives in Milestone 5.
struct ProgressScreen: View {
    @Query(sort: \ExerciseStateModel.exerciseName) private var states: [ExerciseStateModel]
    @Query private var records: [PersonalRecordModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }, sort: \StrengthLogModel.startedAt, order: .reverse)
    private var workouts: [StrengthLogModel]
    @Query private var profiles: [UserProfileModel]
    @Query private var runs: [RunLogModel]

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
                    recentWorkouts
                    LoadTrendCard(report: LoadModel.report(
                        entries: DashboardService.loadEntries(runs: runs, lifts: workouts),
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
                Text("Finish a strength session to see your lifts, records and progress here.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
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
                Text("No sessions yet.").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
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
}
