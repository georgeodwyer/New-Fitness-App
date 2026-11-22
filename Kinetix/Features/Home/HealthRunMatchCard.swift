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
    @AppStorage(HealthMatchFinder.dismissedKey) private var dismissedRaw = ""
    let units: UnitSystem
    /// With nothing to count, show the Getting started checklist instead (one prompt at a time).
    var otherwiseGettingStarted = false

    private var dismissed: Set<UUID> { Set(dismissedRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }) }

    /// Today's planned run shows its own offer inside the session card (HealthMatchStrip).
    var excludingToday = false

    private var suggestion: (HealthRunMatch.Suggestion, PlannedSessionModel)? {
        HealthMatchFinder.first(sessions: sessions, runs: runs, integrations: integrations, dismissed: dismissed) {
            !excludingToday || !Calendar.kinetix.isDateInToday($0.date)
        }
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
        HealthMatchFinder.count(workout, as: session, in: context)
    }

    private func dismiss(_ id: UUID) {
        dismissedRaw = HealthMatchFinder.dismissing(id, in: dismissedRaw)
    }
}

/// Finding a run from Apple Health that lines up with a planned run, and counting it.
enum HealthMatchFinder {
    static let dismissedKey = "healthMatch.dismissed"

    static func dismissed(_ raw: String) -> Set<UUID> {
        Set(raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    static func dismissing(_ id: UUID, in raw: String) -> String {
        var all = dismissed(raw)
        all.insert(id)
        return all.map(\.uuidString).suffix(100).joined(separator: ",")
    }

    @MainActor
    static func first(sessions: [PlannedSessionModel], runs: [RunLogModel], integrations: IntegrationSettings, dismissed: Set<UUID>,
                      where include: (PlannedSessionModel) -> Bool = { _ in true }) -> (HealthRunMatch.Suggestion, PlannedSessionModel)? {
        guard integrations.healthEnabled else { return nil }
        let open = sessions.filter {
            !$0.isSoftDeleted && $0.kind.discipline == .run && ($0.status == .planned || $0.status == .swapped)
                && ($0.plan?.isActive ?? true) && include($0)
        }
        let planned = open.map { HealthRunMatch.Planned(id: $0.id, date: $0.date, meters: $0.estimatedDistanceMeters) }
        let recorded = runs.filter(\.isFinished).map { DateInterval(start: $0.startedAt, duration: max($0.durationSeconds, 60)) }
        guard let first = HealthRunMatch.suggestions(external: integrations.externalWorkouts, recorded: recorded, planned: planned,
                                                     dismissed: dismissed, now: .now, calendar: .kinetix).first,
              let session = open.first(where: { $0.id == first.plannedId }) else { return nil }
        return (first, session)
    }

    @MainActor
    static func count(_ workout: ExternalWorkout, as session: PlannedSessionModel, in context: ModelContext) {
        RunService.logManual(for: session, startedAt: workout.start, durationSeconds: workout.durationSeconds,
                             distanceMeters: workout.distanceMeters ?? 0, effort: session.plannedEffort,
                             averageHeartRate: workout.averageHeartRate, source: RunLogModel.healthSource, in: context)
    }
}

/// Inside today's run card: "Already ran? 5.2 km indoor run in Apple Health · Count it".
struct HealthMatchStrip: View {
    let session: PlannedSessionModel
    let format: DisplayFormat
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<RunLogModel> { $0.deletedAt == nil }) private var runs: [RunLogModel]
    @State private var integrations = IntegrationSettings.shared
    @AppStorage(HealthMatchFinder.dismissedKey) private var dismissedRaw = ""

    var body: some View {
        if let pair = HealthMatchFinder.first(sessions: [session], runs: runs, integrations: integrations,
                                              dismissed: HealthMatchFinder.dismissed(dismissedRaw)) {
            let workout = pair.0.workout
            HStack(spacing: KXSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Already ran?").font(KXFont.captionEmphasis).foregroundStyle(KXColor.ink)
                    Text("\(format.distance(workout.distanceMeters ?? 0)) \(workout.name.lowercased()) in Apple Health")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: KXSpacing.xs)
                Button("Extra") { dismissedRaw = HealthMatchFinder.dismissing(workout.id, in: dismissedRaw) }
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
                    .accessibilityLabel("It was extra")
                    .accessibilityIdentifier("healthMatch.extra")
                Button("Count it") { HealthMatchFinder.count(workout, as: session, in: context) }
                    .buttonStyle(.kx(.primary))
                    .accessibilityIdentifier("healthMatch.count")
            }
            .padding(KXSpacing.sm)
            .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        }
    }
}
