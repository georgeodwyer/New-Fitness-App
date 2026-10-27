import SwiftUI
import TrainingEngine

/// Everything finished today, planned or not: Kinetix runs and gym sessions (phone, Apple
/// Watch, Garmin, Strava imports) and other workouts from Apple Health. Tap one to open it.
struct DoneTodayCard: View {
    enum Item: Identifiable {
        case run(RunLogModel)
        case lift(StrengthLogModel)
        case other(ExternalWorkout)

        var id: String {
            switch self {
            case .run(let run): return run.id.uuidString
            case .lift(let lift): return lift.id.uuidString
            case .other(let workout): return workout.id.uuidString
            }
        }

        var start: Date {
            switch self {
            case .run(let run): return run.startedAt
            case .lift(let lift): return lift.startedAt
            case .other(let workout): return workout.start
            }
        }
    }

    let items: [Item]
    let units: UnitSystem
    let onOpenRun: (RunLogModel) -> Void
    let onOpenLift: (StrengthLogModel) -> Void

    private var format: DisplayFormat { DisplayFormat(units: units) }

    /// Today's items, oldest first. Health workouts that overlap a Kinetix one are left out.
    static func items(runs: [RunLogModel], lifts: [StrengthLogModel], external: [ExternalWorkout], now: Date = .now) -> [Item] {
        let calendar = Calendar.kinetix
        let todaysRuns = runs.filter { $0.isFinished && !$0.isSoftDeleted && calendar.isDate($0.startedAt, inSameDayAs: now) }
        let todaysLifts = lifts.filter { $0.isFinished && !$0.isSoftDeleted && calendar.isDate($0.startedAt, inSameDayAs: now) }
        let intervals = todaysRuns.map { DateInterval(start: $0.startedAt, duration: max($0.durationSeconds, 1)) }
            + todaysLifts.map { DateInterval(start: $0.startedAt, duration: max($0.durationSeconds, 1)) }
        let others = external.filter { workout in
            calendar.isDate(workout.start, inSameDayAs: now) && workout.end > workout.start
                && !intervals.contains { $0.intersects(DateInterval(start: workout.start, end: workout.end)) }
        }
        let all = todaysRuns.map(Item.run) + todaysLifts.map(Item.lift) + others.map(Item.other)
        return all.sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXOverline("Done today", color: KXColor.success)
            ForEach(items) { item in
                row(item)
                if item.id != items.last?.id { Divider() }
            }
        }
        .kxCard()
        .accessibilityIdentifier("today.doneToday")
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        switch item {
        case .run(let run):
            Button { onOpenRun(run) } label: {
                line(symbol: "figure.run", tint: KXColor.run, title: run.title.isEmpty ? "Run" : run.title,
                     detail: runDetail(run), source: run.sourceTag, opens: true)
            }
            .buttonStyle(.plain)
        case .lift(let lift):
            Button { onOpenLift(lift) } label: {
                line(symbol: "dumbbell", tint: KXColor.lift, title: lift.title.isEmpty ? "Gym session" : lift.title,
                     detail: liftDetail(lift), source: nil, opens: true)
            }
            .buttonStyle(.plain)
        case .other(let workout):
            line(symbol: symbol(for: workout.kind), tint: KXColor.other, title: workout.name,
                 detail: otherDetail(workout), source: "Apple Health", opens: false)
        }
    }

    private func line(symbol: String, tint: Color, title: String, detail: String, source: String?, opens: Bool) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(KXColor.success)
                .accessibilityHidden(true)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(KXColor.surfaceTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                Text(detail).font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let source, source != "Planned", source != "Recorded" {
                Text(source).font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
            if opens {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func runDetail(_ run: RunLogModel) -> String {
        var parts = [format.distance(run.distanceMeters)]
        if run.distanceMeters > 50, run.durationSeconds > 0, let pace = Pace(metersPerSecond: run.distanceMeters / run.durationSeconds) {
            parts.append(format.pace(pace))
        }
        parts.append(Units.formatMinutesSeconds(run.durationSeconds))
        return parts.joined(separator: " · ")
    }

    private func liftDetail(_ lift: StrengthLogModel) -> String {
        let sets = lift.orderedSets.filter(\.isCompleted).count
        var parts = ["\(Int((lift.durationSeconds / 60).rounded())) min", "\(sets) set\(sets == 1 ? "" : "s")"]
        if lift.volumeKg > 0 { parts.append(format.volume(lift.volumeKg)) }
        return parts.joined(separator: " · ")
    }

    private func otherDetail(_ workout: ExternalWorkout) -> String {
        var parts = ["\(Int((workout.end.timeIntervalSince(workout.start) / 60).rounded())) min"]
        if let meters = workout.distanceMeters, meters > 0 { parts.append(format.distance(meters)) }
        return parts.joined(separator: " · ")
    }

    private func symbol(for kind: ExternalWorkout.Kind) -> String {
        switch kind {
        case .run: return "figure.run"
        case .strength: return "dumbbell"
        case .cycling: return "bicycle"
        case .walking: return "figure.walk"
        case .other: return "figure.mixed.cardio"
        }
    }
}
