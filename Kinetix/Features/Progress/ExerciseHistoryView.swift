import SwiftUI
import SwiftData
import Charts
import TrainingEngine

/// One exercise over time: estimated 1RM chart, personal records, recent sessions.
struct ExerciseHistoryView: View {
    let exerciseId: String
    let name: String

    @Query private var sets: [SetLogModel]
    @Query private var records: [PersonalRecordModel]
    @Query private var profiles: [UserProfileModel]

    init(exerciseId: String, name: String) {
        self.exerciseId = exerciseId
        self.name = name
        _sets = Query(filter: #Predicate<SetLogModel> { $0.exerciseId == exerciseId && $0.completedAt != nil },
                      sort: \SetLogModel.completedAt)
        _records = Query(filter: #Predicate<PersonalRecordModel> { $0.recordKey == exerciseId })
    }

    private var format: DisplayFormat { DisplayFormat(units: profiles.first?.units ?? .metric) }
    private var units: UnitSystem { profiles.first?.units ?? .metric }

    private struct SessionPoint: Identifiable {
        let date: Date
        let e1rm: Double
        let topSet: String
        let sets: [SetLogModel]
        var id: Date { date }
    }

    /// Best estimated 1RM per finished workout.
    private var points: [SessionPoint] {
        let finished = sets.filter { !$0.isSoftDeleted && ($0.session?.isFinished ?? false) && !$0.isBodyweight }
        let bySession = Dictionary(grouping: finished) { $0.session?.id }
        return bySession.values.compactMap { group -> SessionPoint? in
            guard let session = group.first?.session else { return nil }
            let best = group.max {
                StrengthMath.estimatedOneRepMax(weightKg: $0.actualWeightKg, reps: $0.actualReps)
                    < StrengthMath.estimatedOneRepMax(weightKg: $1.actualWeightKg, reps: $1.actualReps)
            }
            guard let best else { return nil }
            return SessionPoint(
                date: session.startedAt,
                e1rm: StrengthMath.estimatedOneRepMax(weightKg: best.actualWeightKg, reps: best.actualReps),
                topSet: "\(format.weight(best.actualWeightKg)) × \(best.actualReps)",
                sets: group.sorted { $0.setIndex < $1.setIndex }
            )
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                Text(name).font(KXFont.display).foregroundStyle(KXColor.ink)
                chartCard
                recordsCard
                historyCard
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func display(_ kg: Double) -> Double { units == .metric ? kg : Units.kgToLb(kg) }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Estimated 1-rep max", subtitle: "Best set each session (Epley formula)")
            if points.count < 2 {
                Text("Log this lift in at least two sessions to see a trend.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Est. 1RM", display(point.e1rm)))
                        .foregroundStyle(KXColor.accent)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Est. 1RM", display(point.e1rm)))
                        .foregroundStyle(KXColor.accent)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(Units.weightUnitLabel(units))
                .frame(height: 180)
                .accessibilityLabel("Estimated one-rep max over \(points.count) sessions, latest \(format.weight(points.last?.e1rm ?? 0))")
            }
        }
        .kxCard()
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Personal records")
            ForEach(RecordKind.allCases, id: \.self) { kind in
                if let record = records.first(where: { $0.kindRaw == kind.rawValue && !$0.isSoftDeleted }) {
                    HStack {
                        Text(kind.displayName).font(KXFont.body).foregroundStyle(KXColor.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(format.weight(record.value)).font(KXFont.bodyEmphasis.monospacedDigit())
                            Text(record.achievedAt.formatted(.dateTime.day().month().year()))
                                .font(.caption2).foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .kxCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("History")
            ForEach(points.reversed()) { point in
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    HStack {
                        Text(point.date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                            .font(KXFont.bodyEmphasis)
                        Spacer()
                        Text("Top set \(point.topSet)").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Text(point.sets.map { "\(Units.formatWeight(kg: $0.actualWeightKg, units: units))×\($0.actualReps)" }.joined(separator: "  "))
                        .font(KXFont.caption.monospacedDigit())
                        .foregroundStyle(KXColor.inkSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}
