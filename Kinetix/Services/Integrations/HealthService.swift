import Foundation
import Observation
import HealthKit
import CoreLocation
import TrainingEngine

/// Apple Health: saves finished runs (with route) and strength sessions, reads resting
/// heart rate and other apps' workouts, and streams Apple Watch heart rate during runs.
@Observable
@MainActor
final class HealthService {
    static let shared = HealthService()

    enum HealthError: LocalizedError {
        case unavailable
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple Health isn't available on this device."
            case .saveFailed: return "Apple Health didn't save the workout."
            }
        }
    }

    @ObservationIgnored let store: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    /// This morning's resting heart rate compared with usual (nil without enough data).
    private(set) var restingHeartRate: RestingHeartRateSignal?
    private(set) var lastRefresh: Date?

    var isAvailable: Bool { store != nil }

    private static let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
    private let heartRateType = HKQuantityType(.heartRate)
    private let restingType = HKQuantityType(.restingHeartRate)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)

    private var readTypes: Set<HKObjectType> { [heartRateType, restingType, HKObjectType.workoutType()] }
    private var shareTypes: Set<HKSampleType> { [HKObjectType.workoutType(), distanceType, HKSeriesType.workoutRoute()] }

    // MARK: - Permission

    /// Shows Apple's permission sheet (only the first time; later changes are made in the Health app).
    func requestAuthorization() async throws {
        guard let store else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Whether the user allowed Kinetix to save workouts. (Apple doesn't reveal read access.)
    var canSaveWorkouts: Bool {
        store?.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: - Saving

    func saveRun(_ log: RunLogModel) async throws -> UUID {
        guard let store else { throw HealthError.unavailable }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let start = log.startedAt
        let end = max(log.finishedAt ?? start.addingTimeInterval(log.durationSeconds), start.addingTimeInterval(log.durationSeconds))

        try await builder.beginCollection(at: start)
        if log.distanceMeters > 0 {
            let distance = HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: log.distanceMeters),
                                            start: start, end: end)
            try await builder.addSamples([distance])
        }
        try await builder.addMetadata([HKMetadataKeyExternalUUID: log.id.uuidString, HKMetadataKeyIndoorWorkout: false])
        try await builder.endCollection(at: end)
        let finished = try await builder.finishWorkout()
        guard let workout = finished as HKWorkout? else { throw HealthError.saveFailed }

        let route = log.route
        if route.count >= 2 {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            let locations = route.map {
                CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), altitude: 0,
                           horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: start.addingTimeInterval($0.elapsed))
            }
            try await routeBuilder.insertRouteData(locations)
            _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
        return workout.uuid
    }

    func saveStrength(_ log: StrengthLogModel) async throws -> UUID {
        guard let store else { throw HealthError.unavailable }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        let start = log.startedAt
        let end = max(log.finishedAt ?? start, start.addingTimeInterval(max(60, log.durationSeconds)))
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([HKMetadataKeyExternalUUID: log.id.uuidString, HKMetadataKeyIndoorWorkout: true])
        try await builder.endCollection(at: end)
        let finished = try await builder.finishWorkout()
        guard let workout = finished as HKWorkout? else { throw HealthError.saveFailed }
        return workout.uuid
    }

    // MARK: - Reading

    /// Re-reads resting heart rate and other apps' workouts (at most every 15 minutes unless forced).
    func refresh(settings: IntegrationSettings = .shared, force: Bool = false, now: Date = .now) async {
        guard store != nil, settings.healthEnabled else { return }
        if !force, let lastRefresh, now.timeIntervalSince(lastRefresh) < 15 * 60 { return }
        lastRefresh = now
        restingHeartRate = await readRestingHeartRate(now: now)
        if let workouts = await readExternalWorkouts(now: now) {
            settings.externalWorkouts = workouts
        }
    }

    private func readRestingHeartRate(now: Date) async -> RestingHeartRateSignal? {
        guard let store else { return nil }
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -29, to: today) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: restingType, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        // One reading per day: the latest.
        var byDay: [Date: Double] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            if byDay[day] == nil { byDay[day] = sample.quantity.doubleValue(for: Self.heartRateUnit) }
        }
        guard let todayValue = byDay[today] else { return nil }
        let history = byDay.filter { $0.key < today }.map(\.value)
        return RestingHeartRateSignal.assess(today: todayValue, history: history)
    }

    /// Workouts from the last 28 days recorded by other apps. nil if Health couldn't be read.
    private func readExternalWorkouts(now: Date) async -> [ExternalWorkout]? {
        guard let store, let from = Calendar.kinetix.date(byAdding: .day, value: -28, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        guard let workouts = try? await descriptor.result(for: store) else { return nil }
        let ownBundle = Bundle.main.bundleIdentifier
        return workouts
            .filter { $0.sourceRevision.source.bundleIdentifier != ownBundle }
            .map { workout in
                ExternalWorkout(
                    id: workout.uuid,
                    start: workout.startDate,
                    end: workout.endDate,
                    kind: Self.kind(for: workout.workoutActivityType),
                    name: Self.name(for: workout.workoutActivityType),
                    distanceMeters: workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter()),
                    averageHeartRate: workout.statistics(for: heartRateType)?.averageQuantity()?.doubleValue(for: Self.heartRateUnit)
                )
            }
    }

    private static func kind(for type: HKWorkoutActivityType) -> ExternalWorkout.Kind {
        switch type {
        case .running: return .run
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining, .highIntensityIntervalTraining: return .strength
        case .cycling: return .cycling
        case .walking, .hiking: return .walking
        default: return .other
        }
    }

    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Run"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .coreTraining: return "Core"
        case .crossTraining: return "Cross-training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .cycling: return "Ride"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .swimming: return "Swim"
        case .yoga: return "Yoga"
        case .rowing: return "Row"
        case .elliptical: return "Elliptical"
        default: return "Workout"
        }
    }

    // MARK: - Live heart rate

    /// Streams heart-rate samples written to Health from `start` on (e.g. by an Apple Watch
    /// running a workout). Returns the query so it can be stopped.
    func startLiveHeartRate(from start: Date, onSample: @escaping @MainActor (Double, Date) -> Void) -> HKQuery? {
        guard let store, IntegrationSettings.shared.healthEnabled else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let unit = Self.heartRateUnit
        let deliver: @Sendable ([HKSample]?) -> Void = { samples in
            let readings = (samples as? [HKQuantitySample] ?? [])
                .sorted { $0.endDate < $1.endDate }
                .map { ($0.quantity.doubleValue(for: unit), $0.endDate) }
            guard !readings.isEmpty else { return }
            Task { @MainActor in readings.forEach { onSample($0.0, $0.1) } }
        }
        let query = HKAnchoredObjectQuery(type: heartRateType, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { _, samples, _, _, _ in
            deliver(samples)
        }
        query.updateHandler = { _, samples, _, _, _ in deliver(samples) }
        store.execute(query)
        return query
    }

    func stop(_ query: HKQuery?) {
        if let query { store?.stop(query) }
    }
}
