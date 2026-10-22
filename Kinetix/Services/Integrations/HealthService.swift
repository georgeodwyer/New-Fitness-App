import Foundation
import Observation
import HealthKit
import CoreLocation
import TrainingEngine

/// Apple Health: saves finished runs (with route) and strength sessions; reads resting heart
/// rate, HRV, sleep, steps, active energy, VO2 max, breathing rate and other apps' workouts;
/// and streams Apple Watch heart rate during runs. Health readings stay on the phone (they're
/// read fresh, never stored in Kinetix's database or synced).
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
    /// Last night's HRV compared with usual (nil without enough data).
    private(set) var hrv: HRVSignal?
    /// Daily values for the last 30 days, per metric (missing days left out).
    private(set) var metricDays: [HealthMetric: [HealthDay]] = [:]
    /// True when Kinetix hasn't yet asked for some of the Health data it can show
    /// (e.g. after an update added new types).
    private(set) var needsPermission = false
    /// When Health was last read in full (set once the readings are in).
    private(set) var lastRefresh: Date?
    @ObservationIgnored private var isRefreshing = false

    var isAvailable: Bool { store != nil || isSample }

    /// Screenshot tests only: made-up body data instead of reading Health.
    private(set) var isSample = false

    /// Health is connected (or sample data is showing), so body data can be shown.
    var isConnected: Bool { isSample || IntegrationSettings.shared.healthEnabled }

    /// Fills in 30 days of made-up readings (screenshot tests; never used otherwise).
    func loadSample(now: Date = .now) {
        isSample = true
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        func series(_ value: (Int) -> Double) -> [HealthDay] {
            (0..<30).reversed().compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today).map { HealthDay(date: $0, value: value(offset)) }
            }
        }
        let wave = { (offset: Int, size: Double) in sin(Double(offset) * 1.3) * size }
        metricDays = [
            .restingHeartRate: series { 51 + wave($0, 2) + ($0 == 0 ? 6 : 0) },
            .hrv: series { $0 == 0 ? 47 : 62 + wave($0, 6) },
            .sleep: series { 7.3 + wave($0, 0.7) - ($0 == 0 ? 1.1 : 0) },
            .steps: series { 9_500 + wave($0, 3_000) },
            .activeEnergy: series { 620 + wave($0, 180) },
            .vo2Max: series { 49.5 - Double($0) * 0.03 },
            .respiratoryRate: series { 14.2 + wave($0, 0.4) }
        ]
        restingHeartRate = RestingHeartRateSignal.assess(today: metricDays[.restingHeartRate]?.last?.value ?? 51,
                                                         history: metricDays[.restingHeartRate]?.dropLast().map(\.value) ?? [])
        hrv = Self.hrvSignal(from: metricDays[.hrv] ?? [], now: now)
    }

    private static let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
    private let heartRateType = HKQuantityType(.heartRate)
    private let restingType = HKQuantityType(.restingHeartRate)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)

    private let sleepType = HKCategoryType(.sleepAnalysis)

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [heartRateType, restingType, HKObjectType.workoutType(), sleepType]
        for metric in HealthMetric.allCases { if let type = Self.quantityType(for: metric) { types.insert(type) } }
        return types
    }

    private static func quantityType(for metric: HealthMetric) -> HKQuantityType? {
        switch metric {
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .hrv: return HKQuantityType(.heartRateVariabilitySDNN)
        case .steps: return HKQuantityType(.stepCount)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .vo2Max: return HKQuantityType(.vo2Max)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        case .sleep: return nil
        }
    }

    private static func unit(for metric: HealthMetric) -> HKUnit {
        switch metric {
        case .restingHeartRate, .respiratoryRate: return HKUnit.count().unitDivided(by: .minute())
        case .hrv: return .secondUnit(with: .milli)
        case .steps: return .count()
        case .activeEnergy: return .kilocalorie()
        case .vo2Max: return HKUnit(from: "ml/kg*min")
        case .sleep: return .hour()
        }
    }
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
        guard store != nil, settings.healthEnabled, !isSample, !isRefreshing else { return }
        if !force, let lastRefresh, now.timeIntervalSince(lastRefresh) < 15 * 60 { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            // Set last, so anything watching it sees the new readings.
            lastRefresh = now
        }
        restingHeartRate = await readRestingHeartRate(now: now)
        metricDays = await readMetricDays(now: now)
        hrv = Self.hrvSignal(from: metricDays[.hrv] ?? [], now: now)
        needsPermission = await checkNeedsPermission()
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

    /// Health has been read since midnight (readings from an earlier day aren't used for today).
    var isFreshToday: Bool {
        isSample || store == nil || lastRefresh.map { Calendar.kinetix.isDateInToday($0) } ?? false
    }

    /// They normally record sleep: a night in Health in the week before today.
    var tracksSleep: Bool {
        let calendar = Calendar.kinetix
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) else { return false }
        return (metricDays[.sleep] ?? []).contains { $0.date >= weekAgo && !calendar.isDateInToday($0.date) }
    }

    /// Last night's data isn't in yet: Health hasn't been read today, or they track sleep and
    /// last night's sleep hasn't arrived (wearables can take a while to sync in the morning).
    var isWaitingForLastNight: Bool {
        guard isConnected, !isSample else { return false }
        return !isFreshToday || (tracksSleep && lastNightSleepHours == nil)
    }

    /// Hours asleep last night, when Health has it.
    var lastNightSleepHours: Double? {
        guard let last = metricDays[.sleep]?.last, Calendar.kinetix.isDateInToday(last.date) else { return nil }
        return last.value
    }

    /// The latest value of each metric against usual, for metrics with data.
    var trends: [HealthTrend] {
        HealthMetric.allCases.compactMap { metric in
            metricDays[metric].flatMap { HealthTrend.make(metric: metric, days: $0, calendar: .kinetix) }
        }
    }

    private func checkNeedsPermission() async -> Bool {
        guard let store else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
        return status == .shouldRequest
    }

    private func readMetricDays(now: Date) async -> [HealthMetric: [HealthDay]] {
        var result: [HealthMetric: [HealthDay]] = [:]
        for metric in HealthMetric.allCases {
            let days = metric == .sleep ? await readSleepDays(now: now) : await readQuantityDays(metric, now: now)
            if !days.isEmpty { result[metric] = days }
        }
        return result
    }

    /// One value per day: the total for steps and energy, the average for readings.
    private func readQuantityDays(_ metric: HealthMetric, now: Date) async -> [HealthDay] {
        guard let store, let type = Self.quantityType(for: metric) else { return [] }
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        guard let from = calendar.date(byAdding: .day, value: -30, to: today) else { return [] }
        let cumulative = metric.isDailyTotal
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: from, end: now)),
            options: cumulative ? .cumulativeSum : .discreteAverage,
            anchorDate: from,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        let unit = Self.unit(for: metric)
        return collection.statistics().compactMap { statistics in
            let quantity = cumulative ? statistics.sumQuantity() : statistics.averageQuantity()
            guard let value = quantity?.doubleValue(for: unit), value > 0 else { return nil }
            return HealthDay(date: calendar.startOfDay(for: statistics.startDate), value: value)
        }
    }

    /// Hours asleep per night, counted on the day you woke up. When several apps or devices
    /// record the same night (say an Apple Watch and a Whoop), the longest is used.
    private func readSleepDays(now: Date) async -> [HealthDay] {
        guard let store else { return [] }
        let calendar = Calendar.kinetix
        guard let from = calendar.date(byAdding: .day, value: -31, to: calendar.startOfDay(for: now)) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: HKQuery.predicateForSamples(withStart: from, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        var bySource: [String: [Date: Double]] = [:]
        for sample in samples where asleep.contains(sample.value) {
            let source = sample.sourceRevision.source.bundleIdentifier
            let day = calendar.startOfDay(for: sample.endDate)
            bySource[source, default: [:]][day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 3600
        }
        var best: [Date: Double] = [:]
        for nights in bySource.values {
            for (day, hours) in nights { best[day] = max(best[day] ?? 0, hours) }
        }
        return best.filter { $0.value >= 0.5 }.map { HealthDay(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }

    /// Today's HRV against the previous days' readings.
    static func hrvSignal(from days: [HealthDay], now: Date) -> HRVSignal? {
        let calendar = Calendar.kinetix
        guard let latest = days.last, calendar.isDate(latest.date, inSameDayAs: now) else { return nil }
        let history = days.dropLast().filter { now.timeIntervalSince($0.date) <= 31 * 86_400 }.map(\.value)
        return HRVSignal.assess(today: latest.value, history: history)
    }

    /// Workouts from the last 28 days recorded by other apps. nil if Health couldn't be read.
    private func readExternalWorkouts(now: Date) async -> [ExternalWorkout]? {
        guard let store, let from = Calendar.kinetix.date(byAdding: .day, value: -28, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: now)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        guard let workouts = try? await descriptor.result(for: store) else { return nil }
        // Kinetix's own workouts (iPhone and Apple Watch apps) are already in Kinetix.
        let ownBundle = Bundle.main.bundleIdentifier ?? "com.georgeodwyer.kinetix"
        return workouts
            .filter { !$0.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundle) }
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
