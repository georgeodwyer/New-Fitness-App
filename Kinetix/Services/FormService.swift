import Foundation
import SwiftData
import TrainingEngine

/// Keeps race predictions on current form: estimates fitness from the last six weeks of runs,
/// and once a week, when the prediction has moved, leaves a note saying so.
@MainActor
enum FormService {
    private static let vdotKey = "form.vdot"
    private static let sessionsKey = "form.sessions"
    private static let notedWeekKey = "form.notedWeek"

    /// Fitness on current form (nil until there's enough recent training).
    static var formVDOT: Double? {
        let value = UserDefaults.standard.double(forKey: vdotKey)
        return value > 0 ? value : nil
    }
    static var formSessions: Int { UserDefaults.standard.integer(forKey: sessionsKey) }

    /// The VDOT predictions use: current form when known, else the profile's race time.
    static func predictionVDOT(for profile: AthleteProfile) -> Double {
        formVDOT ?? PaceZones(profile: profile).vdot
    }

    /// Training paces are clearly behind current form: worth offering an update.
    static func shouldOfferPaceUpdate(for profile: AthleteProfile) -> Bool {
        guard let form = formVDOT else { return false }
        return form >= PaceZones(profile: profile).vdot * 1.02 && formSessions >= 2
    }

    static func check(profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        let from = now.addingTimeInterval(-42 * 86_400)
        let runs = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
            .filter { $0.countsTowardsHistory && !$0.isImportedFromStrava && $0.startedAt >= from }
        let evidence = runs.map { run in
            FormEstimate.Evidence(
                date: run.startedAt,
                bestEfforts: run.distanceMeters >= 1000 ? RunAnalysis.bestEfforts(route: run.route) : [:],
                intervalRepPaces: run.runType == .intervals
                    ? run.segmentResults.filter { $0.segment.kind == .work && $0.durationSeconds >= 60 && $0.durationSeconds <= 360 }
                        .compactMap(\.averagePace)
                    : [])
        }
        let base = PaceZones(profile: profile).vdot
        let previous = predictionVDOT(for: profile)
        guard let result = FormEstimate.estimate(evidence, current: base, now: now) else { return }
        UserDefaults.standard.set(result.vdot, forKey: vdotKey)
        UserDefaults.standard.set(result.sessions, forKey: sessionsKey)

        // At most one note a week, and only when the goal prediction moved by 5 s or more.
        let calendar = Calendar.kinetix
        let week = Int(calendar.startOfISOWeek(for: now).timeIntervalSince1970)
        guard UserDefaults.standard.integer(forKey: notedWeekKey) != week else { return }
        let meters = goalMeters(profile.goal)
        let before = PaceZones(vdot: previous).predictedTime(distanceMeters: meters)
        let after = PaceZones(vdot: result.vdot).predictedTime(distanceMeters: meters)
        let change = Int((before - after).rounded())
        guard abs(change) >= 5 else { return }
        UserDefaults.standard.set(week, forKey: notedWeekKey)
        let name = distanceName(meters)
        let summary = change > 0
            ? "Your \(name) prediction improved \(Units.formatMinutesSeconds(Double(change))) (now \(Units.formatMinutesSeconds(after))), from your recent training."
            : "Your \(name) prediction slipped \(Units.formatMinutesSeconds(Double(-change))) (now \(Units.formatMinutesSeconds(after))). Recent runs were a bit slower; a good week puts it back."
        context.insert(PlanChangeModel(summary: summary, now: now))
        try? context.save()
    }

    /// Sets training paces from current form (the runner confirmed it) and rebuilds the plan's paces.
    static func applyForm(to model: UserProfileModel, in context: ModelContext) {
        guard let form = formVDOT else { return }
        var profile = model.profile
        let seconds = PaceZones(vdot: form).predictedTime(distanceMeters: 10000)
        profile.recentRace = RaceResult(distanceMeters: 10000, timeSeconds: seconds.rounded())
        model.profile = profile
        model.touch()
        PlanService.rebuildRemainder(for: profile, in: context)
    }

    static func goalMeters(_ goal: TrainingGoal) -> Double {
        switch goal {
        case .first5k, .faster5k: return 5000
        case .halfMarathon: return 21097.5
        case .marathon: return 42195
        default: return 10000
        }
    }

    static func distanceName(_ meters: Double) -> String {
        switch meters {
        case 5000: return "5K"
        case 21097.5: return "half marathon"
        case 42195: return "marathon"
        default: return "10K"
        }
    }
}
