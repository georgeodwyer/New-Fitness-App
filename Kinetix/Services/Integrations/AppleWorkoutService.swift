import Foundation
import SwiftData
import HealthKit
import TrainingEngine
#if canImport(WorkoutKit)
import WorkoutKit
#endif

/// Sends the next week's planned runs to Apple's own Workout app on Apple Watch (WorkoutKit),
/// with each part's distance or time and its pace range as an alert. For people who'd rather
/// run in the Workout app than the Kinetix watch app. Runs done there come back from Health.
@MainActor
@Observable
final class AppleWorkoutService {
    static let shared = AppleWorkoutService()

    private static let enabledKey = "appleWorkout.enabled"
    private static let sentKey = "appleWorkout.lastSent"
    /// Apple allows 15 scheduled workouts per app.
    private static let limit = 15

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    private(set) var lastSentAt: Date?
    private(set) var scheduledCount = 0
    private(set) var message: String?
    private var lastFingerprint: String?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        lastSentAt = UserDefaults.standard.object(forKey: Self.sentKey) as? Date
    }

    var isSupported: Bool {
        #if canImport(WorkoutKit)
        return WorkoutScheduler.isSupported
        #else
        return false
        #endif
    }

    /// Turns sending on (asks for permission the first time) and sends the plan.
    func enable(in context: ModelContext) async {
        #if canImport(WorkoutKit)
        let state = await WorkoutScheduler.shared.requestAuthorization()
        guard state == .authorized else {
            isEnabled = false
            message = "Kinetix isn't allowed to add workouts. You can allow it in the Settings app → Kinetix."
            return
        }
        isEnabled = true
        message = nil
        await sync(in: context, force: true)
        #endif
    }

    func disable() async {
        isEnabled = false
        lastFingerprint = nil
        #if canImport(WorkoutKit)
        await WorkoutScheduler.shared.removeAllWorkouts()
        #endif
        scheduledCount = 0
    }

    /// Replaces what's scheduled with the next 7 days of planned runs (only if they changed).
    func sync(in context: ModelContext, now: Date = .now, force: Bool = false) async {
        #if canImport(WorkoutKit)
        guard isEnabled, isSupported else { return }
        guard await WorkoutScheduler.shared.authorizationState == .authorized else { return }
        let sessions = Self.upcomingRuns(in: context, now: now)
        let fingerprint = sessions.map { "\($0.id)|\($0.date.timeIntervalSince1970)|\($0.runStructureData?.hashValue ?? 0)" }
            .joined(separator: ",")
        guard force || fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint

        await WorkoutScheduler.shared.removeAllWorkouts()
        let units = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.units ?? .metric
        var count = 0
        for session in sessions.prefix(Self.limit) {
            guard let structure = session.runStructure,
                  let workout = Self.workout(title: session.title, structure: structure, units: units) else { continue }
            let plan = WorkoutPlan(.custom(workout), id: session.id)
            var components = Calendar.current.dateComponents([.year, .month, .day], from: session.date)
            components.hour = session.slot == .evening ? 18 : 7
            await WorkoutScheduler.shared.schedule(plan, at: components)
            count += 1
        }
        scheduledCount = count
        lastSentAt = now
        UserDefaults.standard.set(now, forKey: Self.sentKey)
        #endif
    }

    /// Planned (or swapped) runs from today for the next 7 days.
    static func upcomingRuns(in context: ModelContext, now: Date) -> [PlannedSessionModel] {
        let calendar = Calendar.kinetix
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
        let descriptor = FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                              sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(descriptor)) ?? []).filter {
            !$0.isSoftDeleted && ($0.status == .planned || $0.status == .swapped)
                && $0.kind.discipline == .run && $0.runStructure != nil && $0.plan?.isActive != false
        }
    }

    #if canImport(WorkoutKit)
    /// A planned run as a Workout app custom workout: warm-up, repeated blocks, cool-down.
    static func workout(title: String, structure: RunStructure, units: UnitSystem) -> CustomWorkout? {
        let grouped = WorkoutBlocks(structure: structure)
        let blocks = grouped.blocks.map { block in
            IntervalBlock(steps: block.steps.map { segment in
                IntervalStep(segment.kind == .recovery ? .recovery : .work, step: step(for: segment))
            }, iterations: block.iterations)
        }
        guard !blocks.isEmpty || grouped.warmUp != nil else { return nil }
        return CustomWorkout(activity: .running, location: .outdoor, displayName: title,
                             warmup: grouped.warmUp.map(step(for:)), blocks: blocks,
                             cooldown: grouped.coolDown.map(step(for:)))
    }

    private static func step(for segment: RunSegment) -> WorkoutStep {
        let goal: WorkoutGoal
        switch segment.length {
        case .distance(let meters): goal = .distance(meters, .meters)
        case .duration(let seconds): goal = .time(seconds, .seconds)
        }
        // Pace range as a speed alert (the Workout app shows it as pace); none for runs by feel.
        guard let target = segment.targetPace, segment.paceIsGuide != true,
              target.slowest.secondsPerKm > 0, target.fastest.secondsPerKm > 0 else {
            return WorkoutStep(goal: goal)
        }
        let low = Measurement(value: 1000 / target.slowest.secondsPerKm, unit: UnitSpeed.metersPerSecond)
        let high = Measurement(value: 1000 / max(target.fastest.secondsPerKm, 1), unit: UnitSpeed.metersPerSecond)
        guard low.value < high.value else { return WorkoutStep(goal: goal) }
        return WorkoutStep(goal: goal, alert: SpeedRangeAlert(target: low...high, metric: .current))
    }
    #endif
}
