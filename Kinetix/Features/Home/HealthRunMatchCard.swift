import SwiftUI
import SwiftData
import TrainingEngine

/// On Today: a run from Apple Health (Apple's Workout app on a GymKit treadmill, a Garmin…) on a
/// day with a planned run still to do. "Count it" saves it as that planned run (ticked off, with
/// the real distance, time and heart rate); "It was extra" leaves it as extra training.
struct HealthRunMatchCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PlannedSessionModel> { $0.deletedAt == nil }) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<RunLogModel> { $0.deletedAt == nil }) private var runs: [RunLogModel]
    @State private var integrations = IntegrationSettings.shared
    @AppStorage("healthMatch.dismissed") private var dismissedRaw = ""
    let units: UnitSystem
    /// With nothing to count, show the Getting started checklist instead (one prompt at a time).
    var otherwiseGettingStarted = false

    private var dismissed: Set<UUID> { Set(dismissedRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }

    private var suggestion: (HealthRunMatch.Suggestion, PlannedSessionModel)? {
        guard integrations.healthEnabled else { return nil }
        let calendar = Calendar.kinetix
        let open = sessions.filter {
            $0.kind.discipline == .run && ($0.status == .planned || $0.status == .swapped) && ($0.plan?.isActive ?? true)
        }
        let planned = open.map { HealthRunMatch.Planned(id: $0.id, date: $0.date, meters: $0.estimatedDistanceMeters) }
        let recorded = runs.filter(\.isFinished).map { DateInterval(start: $0.startedAt, duration: max($0.durationSeconds, 60)) }
        guard let first = HealthRunMatch.suggestions(external: integrations.externalWorkouts, recorded: recorded, planned: planned,
                                                     dismissed: dismissed, now: .now, calendar: calendar).first,
              let session = open.first(where: { $0.id == first.plannedId }) else { return nil }
        return (first, session)
    }

    var body: some View {
        if let pair = suggestion {
            let session = pair.1
            let workout = pair.0.workout
            let format = DisplayFormat(units: units)
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "heart.text.square.fill").foregroundStyle(KXColor.danger).accessibilityHidden(true)
                    KXOverline("From Apple Health")
                }
                Text("Count your \(format.distance(workout.distanceMeters ?? 0)) \(workout.name.lowercased()) as \(dayWord(session.date)) \(session.title.lowercased())?")
                    .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Units.formatMinutesSeconds(workout.durationSeconds))"
                     + (workout.averageHeartRate.map { " · \(Int($0)) bpm average" } ?? "")
                     + " · \(workout.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                HStack(spacing: KXSpacing.sm) {
                    Button("It was extra") { dismiss(workout.id) }
                        .buttonStyle(.kx(.secondary))
                        .accessibilityIdentifier("healthMatch.extra")
                    Button("Count it") { count(workout, as: session) }
                        .buttonStyle(.kx(.primary, fullWidth: true))
                        .accessibilityIdentifier("healthMatch.count")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxCard()
        } else if otherwiseGettingStarted {
            GettingStartedCard()
        }
    }

    private func dayWord(_ date: Date) -> String {
        let calendar = Calendar.kinetix
        if calendar.isDateInToday(date) { return "today's" }
        if calendar.isDateInYesterday(date) { return "yesterday's" }
        return date.formatted(.dateTime.weekday(.wide)) + "'s"
    }

    private func count(_ workout: ExternalWorkout, as session: PlannedSessionModel) {
        RunService.logManual(for: session, startedAt: workout.start, durationSeconds: workout.durationSeconds,
                             distanceMeters: workout.distanceMeters ?? 0, effort: session.plannedEffort,
                             averageHeartRate: workout.averageHeartRate, source: RunLogModel.healthSource, in: context)
    }

    private func dismiss(_ id: UUID) {
        var all = dismissed
        all.insert(id)
        dismissedRaw = all.map(\.uuidString).suffix(100).joined(separator: ",")
    }
}
