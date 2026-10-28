import SwiftData
import SwiftUI
import TrainingEngine

/// After a planned race or time trial: offers to use the result as the runner's race time,
/// which sets their paces, and rebuilds the rest of the plan with them.
struct PaceUpdateCard: View {
    let log: RunLogModel

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query private var sessions: [PlannedSessionModel]
    @State private var updated = false

    /// The race or time trial's distance, from the planned session's race segment.
    private var raceMeters: Double? {
        guard let id = log.plannedSessionId, let planned = sessions.first(where: { $0.id == id }) else { return nil }
        for segment in planned.runStructure?.segments ?? [] where segment.label == "Race" || segment.label == "Time trial" {
            if case .distance(let meters) = segment.length { return meters }
        }
        return nil
    }

    /// Their time for that distance: the best effort from GPS, or the whole run if it was
    /// about the right length.
    private var result: RaceResult? {
        guard let meters = raceMeters else { return nil }
        if let distance = BestEffortDistance(rawValue: meters),
           let seconds = RunAnalysis.bestEfforts(route: log.route)[distance] {
            return RaceResult(distanceMeters: meters, timeSeconds: seconds)
        }
        guard log.distanceMeters >= meters * 0.97, log.distanceMeters > 0 else { return nil }
        return RaceResult(distanceMeters: meters, timeSeconds: log.durationSeconds * meters / log.distanceMeters)
    }

    private var distanceName: String {
        switch raceMeters ?? 0 {
        case 5000: return "5K"
        case 10000: return "10K"
        case 21097.5: return "half marathon"
        case 42195: return "marathon"
        case let meters: return String(format: "%.1f km", meters / 1000)
        }
    }

    var body: some View {
        if let result, let profileModel = profiles.first {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                KXOverline(updated ? "Paces updated" : "Update your paces", color: updated ? KXColor.success : KXColor.run)
                Text(updated
                     ? "Your paces now come from your \(distanceName) in \(time(result.timeSeconds)). The rest of your plan has been rebuilt with them."
                     : "You ran your \(distanceName) in \(time(result.timeSeconds)). Use it to set your training paces for the rest of the plan?")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                if !updated {
                    Button("Use this result") { apply(result, to: profileModel) }
                        .buttonStyle(.kx(.primary, fullWidth: true))
                        .accessibilityIdentifier("summary.updatePaces")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxCard()
        }
    }

    private func time(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded())
            .formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    private func apply(_ result: RaceResult, to model: UserProfileModel) {
        var profile = model.profile
        profile.recentRace = result
        model.profile = profile
        model.touch()
        PlanService.rebuildRemainder(for: profile, in: context)
        updated = true
    }
}
