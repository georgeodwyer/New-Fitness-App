import Foundation
import Observation
import SwiftData
import HealthKit
import TrainingEngine

/// Live state of a strength workout: grouped sets and the rest timer.
@Observable
@MainActor
final class StrengthWorkoutModel {
    struct ExerciseGroup: Identifiable {
        let key: String
        let name: String
        let sets: [SetLogModel]
        var id: String { key }
        var first: SetLogModel { sets[0] }
        var isComplete: Bool { sets.allSatisfy(\.isCompleted) }
    }

    let log: StrengthLogModel
    let planned: PlannedSessionModel?
    private let context: ModelContext

    /// When the current set started (Start set); nil between sets.
    private(set) var setStartedAt: Date?
    /// The set finished last, kept open for its effort rating until the next set starts.
    private(set) var lastFinishedSetId: UUID?
    /// When this screen opened, for the warm-up timer.
    let warmUpStartedAt = Date()

    /// When the current rest ends (nil = not resting).
    private(set) var restEndsAt: Date?
    private(set) var restTotalSeconds: Double = 0
    /// Increments when a rest finishes (drives haptics).
    private(set) var restFinishedCount = 0
    private var restTask: Task<Void, Never>?

    init(log: StrengthLogModel, planned: PlannedSessionModel?, context: ModelContext, units: UnitSystem = .metric) {
        self.log = log
        self.planned = planned
        self.context = context
        self.units = units
        let profile = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.profile
        let runs = (try? context.fetch(FetchDescriptor<RunLogModel>())) ?? []
        zones = StrainService.zones(profile: profile, runs: runs)
        refreshLastTime()
        WorkoutActivityController.shared.start(title: log.title.isEmpty ? "Strength" : log.title, kind: "strength",
                                               state: lockScreenState)
        startHeartRateAndWatch()
    }

    // MARK: Heart rate and Apple Watch

    enum HeartRateSource { case watch, strap }

    /// The runner's heart-rate zones (age, their own settings or what their runs show).
    let zones: HeartRateZones
    private(set) var heartRate: Double?
    private(set) var heartRateSource: HeartRateSource?
    private(set) var heartRateAt: Date?
    /// Seconds spent in each zone this session (index 0 = below zone 1).
    private(set) var secondsInZone: [Double] = Array(repeating: 0, count: 6)
    /// Showing on the Apple Watch (the Kinetix watch app, recording a strength workout for heart rate).
    private(set) var isOnWatch = false
    /// The watch couldn't be opened (asleep or locked): ask the runner to open Kinetix there.
    private(set) var watchNeedsOpening = false
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var lastStrapAt: Date?

    private func startHeartRateAndWatch() {
        let monitor = HeartRateMonitor.shared
        monitor.onHeartRate = { [weak self] bpm, _ in
            MainActor.assumeIsolated { self?.receiveHeartRate(bpm, from: .strap) }
        }
        monitor.connectToSaved()
        let handlers = WatchMirrorService.Handlers(
            command: { [weak self] command in self?.handleWatch(command) },
            heartRate: { [weak self] bpm, _ in self?.receiveHeartRate(bpm, from: .watch) },
            watchStatus: { [weak self] showing in self?.watchNeedsOpening = !showing }
        )
        isOnWatch = WatchMirrorService.shared.begin(runId: log.id, handlers: handlers, activity: .traditionalStrengthTraining)
        guard isOnWatch else { return }
        publishToWatch()
        // The watch treats silence as a lost phone, so keep it up to date between changes.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishToWatch() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func stopHeartRateAndWatch() {
        watchTimer?.invalidate()
        watchTimer = nil
        if isOnWatch {
            WatchMirrorService.shared.end(saved: true)
            isOnWatch = false
        }
        HeartRateMonitor.shared.onHeartRate = nil
        HeartRateMonitor.shared.disconnect()
    }

    /// A chest strap, when one's connected, wins over the watch.
    private func receiveHeartRate(_ bpm: Double, from source: HeartRateSource) {
        guard bpm > 30, bpm < 250 else { return }
        let now = Date()
        if source == .watch, let strap = lastStrapAt, now.timeIntervalSince(strap) < 10 { return }
        if source == .strap { lastStrapAt = now }
        if let previous = heartRate, let at = heartRateAt {
            secondsInZone[zones.zone(for: previous)] += min(10, max(0, now.timeIntervalSince(at)))
        }
        heartRate = bpm
        heartRateAt = now
        heartRateSource = source
    }

    /// No reading for 20 seconds: show it as gone rather than stale.
    func currentHeartRate(at now: Date) -> Double? {
        guard let heartRateAt, now.timeIntervalSince(heartRateAt) < 20 else { return nil }
        return heartRate
    }

    private func handleWatch(_ command: MirrorCommand) {
        switch command {
        case .startSet: startSet()
        case .finishSet: finishSet()
        case .undo: undoLast()
        default: break
        }
    }

    private func publishToWatch() {
        guard isOnWatch else { return }
        let next = nextSet
        var setText: String?
        if let next, let group = groups.first(where: { $0.sets.contains { $0.id == next.id } }),
           let index = group.sets.firstIndex(where: { $0.id == next.id }) {
            let load = next.isBodyweight ? "\(next.actualReps) reps"
                : DisplayFormat(units: units).set(weightKg: next.actualWeightKg, reps: next.actualReps)
            setText = "Set \(index + 1) of \(group.sets.count) · \(load)"
        }
        let resting = restEndsAt.map { $0 > .now } ?? false
        let frame = GymMirrorFrame(sessionId: log.id, title: log.title.isEmpty ? "Gym" : log.title,
                                   exercise: next?.exerciseName, setText: setText, setStartedAt: setStartedAt,
                                   restEndsAt: resting ? restEndsAt : nil, setsDone: completedSets, setsTotal: totalSets,
                                   zoneStarts: zones.starts, maxHeartRate: zones.maxHeartRate, sentAt: .now)
        WatchMirrorService.shared.publish(frame)
    }

    private let units: UnitSystem

    // MARK: Lock screen

    /// The next set to do, e.g. "Back Squat · set 3 of 5 · 100 kg × 5".
    private var nextSetText: String? {
        guard let group = groups.first(where: { !$0.isComplete }),
              let set = group.sets.first(where: { !$0.isCompleted }),
              let index = group.sets.firstIndex(where: { $0.id == set.id }) else { return nil }
        let load = set.isBodyweight ? "\(set.actualReps) reps"
            : DisplayFormat(units: units).set(weightKg: set.actualWeightKg, reps: set.actualReps)
        return "\(group.name) · set \(index + 1) of \(group.sets.count) · \(load)"
    }

    private var lockScreenState: WorkoutActivityAttributes.ContentState {
        let resting = restEndsAt.map { $0 > .now } ?? false
        return WorkoutActivityAttributes.ContentState(
            mode: resting ? .resting : .lifting,
            timerStart: log.startedAt,
            elapsedSeconds: Date.now.timeIntervalSince(log.startedAt),
            restEndsAt: resting ? restEndsAt : nil,
            setsDone: completedSets,
            setsTotal: totalSets,
            nextSet: nextSetText
        )
    }

    private func updateLockScreen() {
        WorkoutActivityController.shared.update(lockScreenState, important: true)
        publishToWatch()
    }

    /// Call when leaving the workout (finished, discarded or closed).
    func endLockScreen() {
        stopHeartRateAndWatch()
        NotificationService.cancelRest()
        restTask?.cancel()
        restTask = nil
        restEndsAt = nil
        WorkoutActivityController.shared.end()
    }

    var groups: [ExerciseGroup] {
        let sets = log.orderedSets
        var result: [ExerciseGroup] = []
        for set in sets {
            if let last = result.last, last.key == set.progressionKey {
                result[result.count - 1] = ExerciseGroup(key: last.key, name: last.name, sets: last.sets + [set])
            } else {
                result.append(ExerciseGroup(key: set.progressionKey, name: set.exerciseName, sets: [set]))
            }
        }
        return result
    }

    /// The first exercise with sets still to do.
    var currentKey: String? { groups.first { !$0.isComplete }?.key }

    var completedSets: Int { log.orderedSets.filter(\.isCompleted).count }
    var totalSets: Int { log.orderedSets.count }

    func toggleComplete(_ set: SetLogModel) {
        if set.isCompleted {
            set.completedAt = nil
            if let seconds = set.activeSeconds {
                log.activeSeconds = max(0, log.activeSeconds - seconds)
                set.activeSeconds = nil
            }
            if lastFinishedSetId == set.id { lastFinishedSetId = nil }
        } else if set.id == nextSet?.id, setStartedAt != nil {
            // Ticking the set that's being timed is the same as Finish set.
            finishSet()
            return
        } else {
            set.completedAt = .now
            lastFinishedSetId = set.id
            startRest(seconds: Double(set.restSeconds))
        }
        set.touch()
        log.touch()
        save()
        updateLockScreen()
    }

    // MARK: Start set / Finish set

    /// The next set to do, in the workout's order.
    var nextSet: SetLogModel? { log.orderedSets.first { !$0.isCompleted } }

    /// "Bench Press · set 2 of 3 · 60 kg × 8"
    var nextSetSummary: String? { nextSetText }

    /// Time spent in sets so far, including the one under way.
    func activeSeconds(at now: Date) -> Double {
        log.activeSeconds + (setStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Starts timing the next set. Any rest still showing ends (rest is a guide, not a gate).
    /// The last Start set / Finish set, so it can be undone (until the next one).
    private enum LastAction {
        case started
        case finished(setId: UUID, previousStart: Date?, activeSeconds: Double?)
    }
    private var lastAction: LastAction?
    var canUndo: Bool { lastAction != nil }
    /// "Undo finish" or "Undo start", for the button's label.
    var undoLabel: String {
        switch lastAction {
        case .started?: return "Undo start"
        case .finished?: return "Undo finish"
        case nil: return "Undo"
        }
    }

    func startSet() {
        guard nextSet != nil, setStartedAt == nil else { return }
        if restEndsAt != nil { skipRest() }
        lastFinishedSetId = nil
        setStartedAt = .now
        lastAction = .started
        updateLockScreen()
    }

    /// Takes back the last Start set (back to resting) or Finish set (the set is open
    /// again and its timer carries on from when it started).
    func undoLast() {
        switch lastAction {
        case .started?:
            setStartedAt = nil
        case .finished(let setId, let previousStart, let activeSeconds)?:
            guard let set = log.orderedSets.first(where: { $0.id == setId }) else { break }
            log.activeSeconds = max(0, log.activeSeconds - (set.activeSeconds ?? 0))
            set.activeSeconds = activeSeconds
            set.completedAt = nil
            set.touch()
            log.touch()
            restEndsAt = nil
            lastFinishedSetId = nil
            setStartedAt = previousStart
            save()
        case nil:
            return
        }
        lastAction = nil
        updateLockScreen()
    }

    /// Logs the set being done with the weight and reps shown, and starts its rest.
    func finishSet() {
        guard let set = nextSet else { return }
        let now = Date()
        lastAction = .finished(setId: set.id, previousStart: setStartedAt, activeSeconds: set.activeSeconds)
        if let start = setStartedAt {
            let seconds = max(0, now.timeIntervalSince(start))
            set.activeSeconds = seconds
            log.activeSeconds += seconds
        }
        setStartedAt = nil
        set.completedAt = now
        lastFinishedSetId = set.id
        set.touch()
        log.touch()
        save()
        startRest(seconds: Double(set.restSeconds))
        updateLockScreen()
    }

    /// Finishing the workout mid-set: the time so far counts as active, the set stays as it is.
    func endSetTimer() {
        guard let start = setStartedAt else { return }
        log.activeSeconds += max(0, Date.now.timeIntervalSince(start))
        setStartedAt = nil
        save()
    }

    // MARK: Warm-up

    /// The warm-up page shows before the first set of a workout that hasn't had one.
    var needsWarmUp: Bool { log.warmUpSeconds == nil && completedSets == 0 && totalSets > 0 }

    func finishWarmUp(startFirstSet: Bool) {
        log.warmUpSeconds = max(0, Date.now.timeIntervalSince(warmUpStartedAt))
        log.touch()
        save()
        if startFirstSet { startSet() }
    }

    func setRPE(_ value: Double?, for set: SetLogModel) {
        set.rpe = value
        set.touch()
        save()
    }

    func update(_ set: SetLogModel, weight: Double? = nil, reps: Int? = nil) {
        if let weight {
            set.actualWeightKg = max(0, weight)
            // First weight picked for a machine: later sets of it use the same.
            if set.actualWeightKg > 0 {
                for later in log.orderedSets where later.progressionKey == set.progressionKey && later.exerciseId == set.exerciseId
                    && later.setIndex > set.setIndex && !later.isCompleted && later.actualWeightKg == 0 {
                    later.actualWeightKg = set.actualWeightKg
                    later.touch()
                }
            }
        }
        if let reps { set.actualReps = max(0, reps) }
        set.touch()
        save()
    }

    // MARK: Your own workouts

    /// "Last time: 3 × 8 @ 60 kg" per exercise id.
    private(set) var lastTime: [String: String] = [:]
    /// Set after "Save as template" so the screen can confirm it.
    private(set) var savedTemplateName: String?

    /// Exercises can be added to, or removed from, workouts started on the Record tab.
    var canEditExercises: Bool { log.isRecorded }

    var exerciseIds: Set<String> { Set(log.orderedSets.map(\.exerciseId)) }

    private func refreshLastTime() {
        var result: [String: String] = [:]
        for group in groups {
            let first = group.first
            if let text = GymService.lastTimeText(exerciseId: first.exerciseId, isBodyweight: first.isBodyweight,
                                                  units: units, excluding: log, in: context) {
                result[first.exerciseId] = text
            }
        }
        lastTime = result
    }

    func addExercise(_ exercise: ExerciseDefinition) {
        GymService.addExercise(GymTemplateItem.starter(for: exercise), to: log, in: context)
        refreshLastTime()
        updateLockScreen()
    }

    func removeExercise(_ group: ExerciseGroup) {
        GymService.removeExercise(key: group.key, from: log, in: context)
        updateLockScreen()
    }

    func saveAsTemplate() {
        let items = GymService.items(from: log)
        guard !items.isEmpty else { return }
        let template = GymTemplateModel(name: log.title, items: items)
        template.lastUsedAt = .now
        context.insert(template)
        save()
        SyncService.shared.requestSync()
        savedTemplateName = log.title
    }

    // MARK: Reorder and swap

    /// Moves an exercise before another (nil = to the end).
    func move(_ key: String, before target: String?) {
        WorkoutEditService.move(key: key, before: target, in: log, context: context)
        updateLockScreen()
    }

    /// A swap that could be kept for next time (asked after swapping).
    struct PendingKeep: Identifiable {
        let id = UUID()
        let fromId: String
        let fromName: String
        let to: ExerciseDefinition
        let target: WorkoutEditService.KeepTarget
    }
    var pendingKeep: PendingKeep?
    /// Shown briefly after a swap is kept.
    private(set) var keptMessage: String?

    /// The runner's equipment, for suggesting swaps.
    var equipment: Equipment {
        ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.profile.equipment ?? .fullGym
    }

    func swap(_ group: ExerciseGroup, to exercise: ExerciseDefinition) {
        let fromId = group.first.exerciseId
        let fromName = group.name
        WorkoutEditService.swap(key: group.key, to: exercise, in: log, context: context)
        refreshLastTime()
        updateLockScreen()
        if let target = WorkoutEditService.keepTarget(for: log, exerciseId: exercise.id, context: context) {
            pendingKeep = PendingKeep(fromId: fromId, fromName: fromName, to: exercise, target: target)
        }
    }

    func keepSwap() {
        guard let pending = pendingKeep else { return }
        WorkoutEditService.keep(from: pending.fromId, to: pending.to, log: log, context: context)
        switch pending.target {
        case .planDay(let day): keptMessage = "\(pending.to.name) is now in your \(day) sessions"
        case .savedWorkout(let name): keptMessage = "\(pending.to.name) saved to \u{201C}\(name)\u{201D}"
        }
        pendingKeep = nil
    }

    func addSet(to group: ExerciseGroup) {
        guard let last = group.sets.last else { return }
        StrengthService.addSet(after: last, to: log, in: context)
        save()
    }

    // MARK: Rest timer

    func startRest(seconds: Double) {
        guard seconds > 0 else { return }
        restTotalSeconds = seconds
        restEndsAt = Date.now.addingTimeInterval(seconds)
        scheduleRestEnd()
        updateLockScreen()
    }

    func extendRest(by seconds: Double) {
        guard let end = restEndsAt else { return }
        restEndsAt = end.addingTimeInterval(seconds)
        restTotalSeconds += seconds
        scheduleRestEnd()
        updateLockScreen()
    }

    func skipRest() {
        restTask?.cancel()
        NotificationService.cancelRest()
        restEndsAt = nil
        updateLockScreen()
    }

    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let end = restEndsAt else { NotificationService.cancelRest(); return }
        NotificationService.scheduleRestEnd(at: end, next: nextSetText)
        restTask = Task { [weak self] in
            let delay = end.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.restEndsAt = nil
            self?.restFinishedCount += 1
            self?.updateLockScreen()
        }
    }

    private func save() {
        try? context.save()
    }
}
