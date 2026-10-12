import SwiftUI
import SwiftData
import TrainingEngine

/// Strength progress: weekly volume, each lift's working weight and best, and every session.
struct StrengthProgressView: View {
    let units: UnitSystem

    @Query(sort: \ExerciseStateModel.exerciseName) private var states: [ExerciseStateModel]
    @Query private var records: [PersonalRecordModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }, sort: \StrengthLogModel.startedAt, order: .reverse)
    private var workouts: [StrengthLogModel]

    private var format: DisplayFormat { DisplayFormat(units: units) }
    private var finished: [StrengthLogModel] { workouts.filter { !$0.isSoftDeleted } }

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
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            WeeklyBarChart(title: "Weekly volume", weeks: weeklyVolume, unitLabel: Units.weightUnitLabel(units),
                           seriesName: "Lifting", color: KXColor.lift, valueFormatter: { format.weight($0) },
                           scale: { units == .metric ? $0 : Units.kgToLb($0) })
            liftsSection
            historyCard
        }
        .navigationDestination(for: ExerciseStateModel.self) { state in
            ExerciseHistoryView(exerciseId: state.exerciseId, name: state.exerciseName)
        }
    }

    private var weeklyVolume: [WeeklyTotal] {
        TrainingHistory.weekly(finished.map { (date: $0.startedAt, value: $0.volumeKg) }, weeks: 12, today: .now, calendar: .kinetix)
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
                                Text(format.weight(e1rm)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
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

    private var months: [(month: Date, sessions: [StrengthLogModel])] {
        let calendar = Calendar.kinetix
        let grouped = Dictionary(grouping: finished) { calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("All strength sessions", subtitle: "\(finished.count) session\(finished.count == 1 ? "" : "s")")
            if finished.isEmpty {
                KXEmptyState(symbol: "list.bullet.rectangle", title: "No strength sessions yet",
                             message: "Completed sessions appear here. Tap one to see every set.")
            }
            ForEach(months, id: \.month) { group in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(group.month.formatted(.dateTime.month(.wide).year()))
                    ForEach(group.sessions) { workout in
                        NavigationLink {
                            StrengthSessionDetailView(log: workout, units: units)
                        } label: {
                            HStack(spacing: KXSpacing.md) {
                                VStack(spacing: 0) {
                                    Text(workout.startedAt.formatted(.dateTime.day())).font(KXFont.bodyEmphasis.monospacedDigit())
                                    Text(workout.startedAt.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                                        .foregroundStyle(KXColor.inkSecondary)
                                }
                                .frame(width: 36)
                                .foregroundStyle(KXColor.ink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.title.isEmpty ? "Strength" : workout.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                    Text("\(workout.orderedSets.filter(\.isCompleted).count) sets · \(Int((workout.durationSeconds / 60).rounded())) min")
                                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                }
                                Spacer()
                                Text(format.weight(workout.volumeKg)).font(KXFont.callout.monospacedDigit()).foregroundStyle(KXColor.ink)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
                            }
                            .padding(.vertical, KXSpacing.xxs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("progress.strengthSession")
                    }
                }
            }
        }
        .kxCard()
    }
}

/// Every set of a finished strength session, with its totals and the records set that day.
struct StrengthSessionDetailView: View {
    let log: StrengthLogModel
    let units: UnitSystem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [PersonalRecordModel]
    @State private var editing = false
    @State private var confirmDelete = false

    private var format: DisplayFormat { DisplayFormat(units: units) }

    private var exercises: [(key: String, sets: [SetLogModel])] {
        let sets = log.orderedSets
        var keys: [String] = []
        for set in sets where !keys.contains(set.progressionKey) { keys.append(set.progressionKey) }
        return keys.map { key in (key, sets.filter { $0.progressionKey == key }) }
    }

    /// Records whose date falls within this session.
    private var recordsSet: [PersonalRecordModel] {
        let end = log.finishedAt ?? log.startedAt.addingTimeInterval(max(log.durationSeconds, 3600))
        let ids = Set(log.sets.map(\.exerciseId))
        return records.filter {
            !$0.isSoftDeleted && ids.contains($0.recordKey) && $0.achievedAt >= log.startedAt.addingTimeInterval(-60) && $0.achievedAt <= end.addingTimeInterval(60)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(log.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()), color: KXColor.lift)
                    Text(log.title.isEmpty ? "Strength" : log.title).font(KXFont.display).foregroundStyle(KXColor.ink)
                }
                HStack {
                    KXMetric(label: "Volume", value: format.weight(log.volumeKg), size: .small)
                    Spacer()
                    KXMetric(label: "Time", value: Units.formatMinutesSeconds(log.durationSeconds), size: .small)
                    Spacer()
                    KXMetric(label: "Effort", value: "\(Int(log.effort))", unit: "/10", size: .small)
                    Spacer()
                    KXMetric(label: "Load", value: "\(Int(log.load.rounded()))", size: .small)
                }
                .kxCard()

                if !recordsSet.isEmpty {
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXSectionHeader("Records set")
                        ForEach(recordsSet) { record in
                            Label {
                                Text("\(exerciseName(record.recordKey)): \(RecordKind(rawValue: record.kindRaw)?.displayName ?? record.kindRaw) \(recordValue(record))")
                                    .font(KXFont.callout).foregroundStyle(KXColor.ink)
                            } icon: {
                                Image(systemName: "medal.fill").foregroundStyle(KXColor.warning)
                            }
                        }
                    }
                    .kxCard()
                }

                ForEach(exercises, id: \.key) { exercise in
                    exerciseCard(exercise.sets)
                }

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete session", systemImage: "trash")
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle(log.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Edit") { editing = true } }
        .sheet(isPresented: $editing) {
            EditSessionSheet(title: log.title, effort: log.effort, kind: "session") { title, effort in
                StrengthService.update(log, title: title, effort: effort, in: context)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                StrengthService.delete(log, in: context)
                dismiss()
            }
        } message: {
            Text("It's removed from Kinetix and your training load. Working weights and records already set are kept. Copies in Apple Health or on Strava aren't affected.")
        }
    }

    private func exerciseName(_ id: String) -> String {
        log.sets.first { $0.exerciseId == id }?.exerciseName ?? id
    }

    private func recordValue(_ record: PersonalRecordModel) -> String {
        record.kindRaw == RecordKind.sessionVolume.rawValue || record.kindRaw == RecordKind.estimatedOneRepMax.rawValue
            || record.kindRaw == RecordKind.heaviestWeight.rawValue ? format.weight(record.value) : String(Int(record.value))
    }

    private func exerciseCard(_ sets: [SetLogModel]) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            if let first = sets.first {
                KXSectionHeader(first.exerciseName.isEmpty ? first.exerciseId : first.exerciseName,
                                subtitle: "Target \(first.repRangeLower)–\(first.repRangeUpper) reps")
            }
            ForEach(sets) { set in
                HStack {
                    Text("Set \(set.setIndex + 1)").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary).frame(width: 52, alignment: .leading)
                    if set.isCompleted {
                        Text(set.isBodyweight ? "\(set.actualReps) reps" : "\(format.weight(set.actualWeightKg)) × \(set.actualReps)")
                            .font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                    } else {
                        Text("Not done").font(KXFont.callout).foregroundStyle(KXColor.inkTertiary)
                    }
                    Spacer()
                    if let rpe = set.rpe {
                        Text("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1))))")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}
