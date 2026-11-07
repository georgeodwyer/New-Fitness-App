import SwiftUI
import SwiftData
import Charts
import TrainingEngine

/// Strength progress: the lifts they track (estimated 1-rep max over time), weekly volume,
/// every lift they've done, and every session.
struct StrengthProgressView: View {
    let units: UnitSystem

    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }, sort: \StrengthLogModel.startedAt, order: .reverse)
    private var workouts: [StrengthLogModel]
    @Query(filter: #Predicate<SetLogModel> { $0.completedAt != nil }) private var doneSets: [SetLogModel]
    @Query(filter: #Predicate<CustomExerciseModel> { $0.deletedAt == nil }) private var customExercises: [CustomExerciseModel]
    /// The lifts shown with graphs (exercise ids, comma separated); empty = the main lifts.
    @AppStorage("progress.trackedLifts") private var trackedRaw = ""
    @State private var choosing = false

    private var format: DisplayFormat { DisplayFormat(units: units) }
    private var finished: [StrengthLogModel] { workouts.filter { !$0.isSoftDeleted } }

    /// Shown first when they haven't chosen: the big lifts.
    static let mainLifts = ["barbell-back-squat", "barbell-bench-press", "barbell-deadlift", "barbell-overhead-press"]

    /// One lift's history: its best estimated 1RM each session.
    struct Lift: Identifiable {
        let id: String
        let name: String
        let points: [(date: Date, e1rm: Double)]
        let isBodyweight: Bool
        let sessions: Int
        var best: Double? { points.map(\.e1rm).max() }
        var latest: Double? { points.last?.e1rm }
        /// Change over the last 12 weeks (latest against the first in that time).
        var change: Double? {
            let since = Date.now.addingTimeInterval(-84 * 86_400)
            guard let first = points.first(where: { $0.date >= since }), let latest, points.count >= 2 else { return nil }
            return latest - first.e1rm
        }
    }

    private func name(of id: String, fallback: String) -> String {
        if let library = PlanService.templates.exercise(id: id) { return library.name }
        if let custom = customExercises.first(where: { $0.exerciseId == id }) { return custom.name }
        return fallback.isEmpty ? id.replacingOccurrences(of: "-", with: " ").capitalized : fallback
    }

    /// Every lift done, most-done first.
    private var lifts: [Lift] {
        let sets = doneSets.filter { set in
            guard let session = set.session else { return false }
            return !set.isSoftDeleted && !session.isSoftDeleted && session.isFinished
        }
        return Dictionary(grouping: sets, by: \.exerciseId).map { id, sets in
            let bySession = Dictionary(grouping: sets) { $0.session?.id }
            let points = bySession.values.compactMap { group -> (date: Date, e1rm: Double)? in
                guard let date = group.first?.session?.startedAt else { return nil }
                let best = group.map { StrengthMath.estimatedOneRepMax(weightKg: $0.actualWeightKg, reps: $0.actualReps) }.max() ?? 0
                return best > 0 ? (date, best) : nil
            }.sorted { $0.date < $1.date }
            let fallback = sets.first { !$0.exerciseName.isEmpty }?.exerciseName ?? ""
            return Lift(id: id, name: name(of: id, fallback: fallback), points: points,
                        isBodyweight: sets.allSatisfy(\.isBodyweight), sessions: bySession.count)
        }
        .sorted { $0.sessions != $1.sessions ? $0.sessions > $1.sessions : $0.name < $1.name }
    }

    private var trackedIds: [String] {
        let chosen = trackedRaw.split(separator: ",").map(String.init)
        if !chosen.isEmpty { return chosen }
        let done = Set(lifts.map(\.id))
        let main = Self.mainLifts.filter(done.contains)
        return main.isEmpty ? Array(lifts.filter { !$0.isBodyweight }.prefix(3).map(\.id)) : main
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            trackedSection
            WeeklyBarChart(title: "Weekly volume", weeks: weeklyVolume, unitLabel: format.volumeUnit,
                           seriesName: "Lifting", color: KXColor.lift, valueFormatter: { format.volume($0) },
                           scale: { units == .metric ? $0 / 1000 : Units.kgToLb($0) })
            liftsSection
            historyCard
        }
        .sheet(isPresented: $choosing) {
            ChooseLiftsSheet(lifts: lifts.map { ($0.id, $0.name) }, selected: Set(trackedIds)) { ids in
                trackedRaw = ids.joined(separator: ",")
            }
        }
    }

    private var weeklyVolume: [WeeklyTotal] {
        TrainingHistory.weekly(finished.map { (date: $0.startedAt, value: $0.volumeKg) }, weeks: 12, today: .now, calendar: .kinetix)
    }

    // MARK: Tracked lifts

    private var trackedSection: some View {
        let byId = Dictionary(lifts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tracked = trackedIds.compactMap { byId[$0] }
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Your lifts", subtitle: "Estimated 1-rep max, best set each session") {
                Button("Choose") { choosing = true }
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.accent)
                    .disabled(lifts.isEmpty)
                    .accessibilityIdentifier("progress.chooseLifts")
            }
            if tracked.isEmpty {
                KXEmptyState(symbol: "chart.line.uptrend.xyaxis", title: "No lifts to show yet",
                             message: "Finish a gym session and your squat, bench, deadlift and overhead press show here with a graph. Tap Choose to pick others.")
            }
            ForEach(tracked) { lift in
                NavigationLink {
                    ExerciseHistoryView(exerciseId: lift.id, name: lift.name)
                } label: {
                    LiftTrendRow(lift: lift, format: format, units: units)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("progress.trackedLift")
            }
        }
        .kxCard()
    }

    // MARK: All lifts

    private var liftsSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("All lifts", subtitle: "\(lifts.count) exercise\(lifts.count == 1 ? "" : "s") · tap for history")
            if lifts.isEmpty {
                KXEmptyState(symbol: "dumbbell", title: "No lifts yet",
                             message: "Finish a strength session to see your lifts, records and progress here.")
            }
            ForEach(lifts) { lift in
                NavigationLink {
                    ExerciseHistoryView(exerciseId: lift.id, name: lift.name)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(lift.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                            Text("\(lift.sessions) session\(lift.sessions == 1 ? "" : "s")")
                                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        Spacer()
                        if let best = lift.best, !lift.isBodyweight {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(format.weight(best)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                                Text("best est. 1RM").font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary)
                            }
                        }
                        Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
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
                                    Text(workout.startedAt.formatted(.dateTime.weekday(.abbreviated))).font(KXFont.caption2)
                                        .foregroundStyle(KXColor.inkSecondary)
                                }
                                .frame(width: 36)
                                .foregroundStyle(KXColor.ink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout.title.isEmpty ? "Strength" : workout.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                    Text("\(workout.orderedSets.filter(\.isCompleted).count) sets · \(Int((workout.durationSeconds / 60).rounded())) min\(workout.isManual ? " · Logged by hand" : workout.isRecorded ? " · Recorded" : "")")
                                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                }
                                Spacer()
                                Text(format.volume(workout.volumeKg)).font(KXFont.callout.monospacedDigit()).foregroundStyle(KXColor.ink)
                                Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
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

/// A tracked lift: name, latest and best estimated 1RM, change over 12 weeks and a small graph.
private struct LiftTrendRow: View {
    let lift: StrengthProgressView.Lift
    let format: DisplayFormat
    let units: UnitSystem

    private func display(_ kg: Double) -> Double { units == .metric ? kg : Units.kgToLb(kg) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(lift.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Spacer()
                if let latest = lift.latest {
                    Text(format.weight(latest)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                }
                Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
            }
            HStack(spacing: KXSpacing.sm) {
                if let best = lift.best { Text("Best \(format.weight(best))") }
                if let change = lift.change, abs(change) >= 0.5 {
                    Text("\(change > 0 ? "▲" : "▼") \(format.weight(abs(change))) in 12 weeks")
                        .foregroundStyle(change > 0 ? KXColor.success : KXColor.warning)
                }
            }
            .font(KXFont.caption)
            .foregroundStyle(KXColor.inkSecondary)
            if lift.points.count >= 2 {
                Chart(Array(lift.points.suffix(20).enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Est. 1RM", display(point.e1rm)))
                        .foregroundStyle(KXColor.lift)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Est. 1RM", display(point.e1rm)))
                        .foregroundStyle(KXColor.lift)
                        .symbolSize(18)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .frame(height: 70)
                .accessibilityHidden(true)
            } else {
                Text("A graph appears after two sessions.").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
        }
        .padding(.vertical, KXSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Pick the lifts shown with graphs.
private struct ChooseLiftsSheet: View {
    let lifts: [(id: String, name: String)]
    @State var selected: Set<String>
    let onSave: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(lifts, id: \.id) { lift in
                        Button {
                            if selected.contains(lift.id) { selected.remove(lift.id) } else { selected.insert(lift.id) }
                        } label: {
                            HStack {
                                Text(lift.name).foregroundStyle(KXColor.ink)
                                Spacer()
                                if selected.contains(lift.id) {
                                    Image(systemName: "checkmark").foregroundStyle(KXColor.accent)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Your lifts show at the top of Progress with a graph of your estimated 1-rep max.")
                }
            }
            .navigationTitle("Choose lifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Keep the order of the list (most done first).
                        onSave(lifts.map(\.id).filter(selected.contains))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
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
    @State private var sharing = false

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
                    KXOverline(log.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()),
                               color: log.isFunctional ? KXColor.functional : KXColor.lift)
                    Text(log.title.isEmpty ? "Strength" : log.title).font(KXFont.display).foregroundStyle(KXColor.ink)
                }
                HStack {
                    if let functional = log.functional {
                        KXMetric(label: "Stations", value: "\(functional.splits.filter { $0.kind != .rest }.count)", size: .small)
                    } else {
                        KXMetric(label: "Volume", value: format.volume(log.volumeKg), size: .small)
                    }
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

                if let functional = log.functional {
                    FunctionalSplitsCard(record: functional, units: units)
                } else {
                    SaveAsTemplateButton(source: .gym(log))
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
        .toolbar {
            Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $sharing) {
            ShareSessionView(source: .strength(log, records: recordsSet.count), units: units)
        }
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
