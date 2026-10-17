import Foundation
import Observation
import SwiftData
import KinetixSync
import TrainingEngine

/// Strava connection (tokens kept in the Keychain on this iPhone), activity uploads, and
/// importing activities recorded elsewhere (runs into history; everything into load).
@Observable
@MainActor
final class StravaService {
    enum State: Equatable {
        /// This build has no Strava client ID / Supabase project (see docs/STRAVA.md).
        case unavailable
        case disconnected
        case connected(athleteName: String?)
    }

    static let shared = StravaService()
    private static let keychainAccount = "strava"

    private(set) var state: State = .unavailable
    /// The athlete allowed Kinetix to read their activities (needed for importing).
    private(set) var canReadActivities = false
    /// Runs and other activities brought in by the last import.
    private(set) var lastImportCount: Int?
    @ObservationIgnored private var importing = false
    @ObservationIgnored private(set) var client: StravaClient?
    @ObservationIgnored private let useKeychain: Bool
    /// The `state` value sent to Strava, checked when it redirects back.
    @ObservationIgnored private var pendingState: String?

    init(config: StravaConfig? = StravaConfig(info: Bundle.main.infoDictionary), transport: HTTPTransport = URLSessionTransport(),
         useKeychain: Bool = true) {
        self.useKeychain = useKeychain
        guard let config else { return }
        let stored = useKeychain ? Keychain.load(account: Self.keychainAccount).flatMap { try? JSONDecoder().decode(StravaTokens.self, from: $0) } : nil
        let client = StravaClient(config: config, transport: transport, tokens: stored)
        self.client = client
        state = stored.map { .connected(athleteName: $0.athleteName) } ?? .disconnected
        canReadActivities = stored?.canReadActivities ?? false
        Task {
            await client.setTokenObserver { tokens in
                Task { @MainActor in StravaService.tokensChanged(tokens, service: self) }
            }
        }
    }

    private static func tokensChanged(_ tokens: StravaTokens?, service: StravaService) {
        if service.useKeychain {
            if let tokens, let data = try? JSONEncoder().encode(tokens) {
                Keychain.save(data, account: keychainAccount)
            } else {
                Keychain.delete(account: keychainAccount)
            }
        }
        service.state = tokens.map { .connected(athleteName: $0.athleteName) } ?? .disconnected
        service.canReadActivities = tokens?.canReadActivities ?? false
        if tokens == nil {
            IntegrationSettings.shared.stravaConnectedAt = nil
            IntegrationSettings.shared.stravaLastImport = nil
            IntegrationSettings.shared.stravaWorkouts = []
        }
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    // MARK: - Connecting

    /// The Strava permission page to show in a web authentication session.
    func beginAuthorization() -> URL? {
        guard let client else { return nil }
        let state = UUID().uuidString
        pendingState = state
        return client.authorizeURL(state: state)
    }

    /// Finishes connecting with the URL Strava redirected to.
    func completeAuthorization(callback: URL) async throws {
        guard let client, let expected = pendingState else { throw StravaError.invalidCallback }
        pendingState = nil
        let code = try StravaClient.authorizationCode(from: callback, expectedState: expected)
        try await client.connect(code: code, scopes: StravaClient.grantedScopes(from: callback))
        IntegrationSettings.shared.stravaConnectedAt = .now
        IntegrationSettings.shared.stravaLastImport = nil
    }

    func disconnect() async {
        await client?.disconnect()
        IntegrationSettings.shared.stravaConnectedAt = nil
    }

    // MARK: - Importing

    /// How far back the first import looks.
    static let firstImportDays = 90
    /// Non-run activities are only kept this long (they only matter for training load).
    static let workoutWindowDays = 28

    /// Fetches activities since the last check (at most every 15 minutes unless forced):
    /// runs become Kinetix runs (history, totals, load); rides, gym sessions and the rest
    /// count towards load. Activities Kinetix uploaded, or already has, are skipped.
    func importRecent(in context: ModelContext, settings: IntegrationSettings = .shared, force: Bool = false,
                      now: Date = .now) async {
        guard let client, isConnected, canReadActivities, settings.stravaImportEnabled, !importing else { return }
        if !force, let last = settings.stravaLastImport, now.timeIntervalSince(last) < 15 * 60 { return }
        importing = true
        defer { importing = false }

        let calendar = Calendar.kinetix
        let firstDay = calendar.date(byAdding: .day, value: -Self.firstImportDays, to: now) ?? now
        // Look back a day before the last check, for activities uploaded to Strava late.
        let after = settings.stravaLastImport.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }.map { max($0, firstDay) } ?? firstDay
        var activities: [StravaActivity] = []
        do {
            for page in 1...5 {
                let batch = try await client.activities(after: after, page: page, perPage: 100)
                activities += batch
                if batch.count < 100 { break }
            }
        } catch {
            return // Offline or Strava busy: tried again next time.
        }

        let runs = (try? context.fetch(FetchDescriptor<RunLogModel>())) ?? []
        let lifts = (try? context.fetch(FetchDescriptor<StrengthLogModel>())) ?? []
        let plan = StravaImport.plan(activities: activities,
                                     knownActivityIds: Set((runs.compactMap(\.stravaActivityId) + lifts.compactMap(\.stravaActivityId))),
                                     kinetixSessions: runs.filter { $0.isFinished && !$0.isSoftDeleted && !$0.isImportedFromStrava }.map(\.interval)
                                        + lifts.filter { $0.isFinished && !$0.isSoftDeleted }.map(\.interval))
        let maxHeartRate = runs.compactMap(\.maxHeartRate).max()
        for activity in plan.runs {
            context.insert(Self.runLog(from: activity, maxHeartRate: maxHeartRate))
        }
        let windowStart = calendar.date(byAdding: .day, value: -Self.workoutWindowDays, to: now) ?? now
        let kept = settings.stravaWorkouts.filter { workout in
            workout.start >= windowStart && !plan.workouts.contains { $0.id == workout.id }
        }
        settings.stravaWorkouts = (kept + plan.workouts.filter { $0.start >= windowStart }).sorted { $0.start < $1.start }
        settings.stravaLastImport = now
        lastImportCount = plan.runs.count + plan.workouts.count
        if !plan.runs.isEmpty {
            try? context.save()
            SyncService.shared.requestSync()
        }
    }

    /// A Kinetix run made from a Strava activity. Effort is estimated from heart rate (or a
    /// typical easy-run value), as for other apps' workouts.
    static func runLog(from activity: StravaActivity, maxHeartRate: Double?) -> RunLogModel {
        let log = RunLogModel(plannedSessionId: nil, startedAt: activity.startDate)
        let duration = Double(activity.movingTime > 0 ? activity.movingTime : activity.elapsedTime)
        log.title = activity.name
        log.durationSeconds = duration
        log.distanceMeters = activity.distance
        log.averageHeartRate = activity.averageHeartrate
        log.maxHeartRate = activity.maxHeartrate
        log.stravaActivityId = String(activity.id)
        log.importSourceRaw = "strava"
        log.isFinished = true
        log.finishedAt = activity.endDate
        let points = activity.routeCoordinates
        if points.count >= 2 {
            // The summary map has no timestamps: spread the run's time evenly along it.
            let route = points.enumerated().map { index, point in
                RoutePoint(latitude: point.latitude, longitude: point.longitude,
                           elapsed: duration * Double(index) / Double(points.count - 1))
            }
            log.routeData = StoredJSON.encode(route)
        }
        let workout = ExternalWorkout(id: UUID(), start: activity.startDate, end: activity.endDate, kind: .run,
                                      name: activity.name, distanceMeters: activity.distance, averageHeartRate: activity.averageHeartrate)
        log.effort = workout.estimatedEffort(maxHeartRate: maxHeartRate ?? activity.maxHeartrate.map { $0 + 5 })
        log.load = SessionLoad.srpe(durationSeconds: duration, effort: log.effort)
        return log
    }

    // MARK: - Uploads

    /// Uploads a run with its GPS route. Returns the Strava activity id.
    func upload(run log: RunLogModel) async throws -> String {
        guard let client else { throw StravaError.notConnected }
        let heartRate = StoredJSON.decode([HeartRateSample].self, from: log.heartRateData) ?? []
        let route = log.route
        let description = Self.runDescription(log)
        if route.count >= 2 {
            let gpx = GPXBuilder.gpx(name: log.title, start: log.startedAt, route: route, heartRate: heartRate)
            return String(try await client.uploadGPX(gpx, name: log.title, description: description, externalId: "kinetix-\(log.id.uuidString)"))
        }
        // No GPS (e.g. treadmill): a manual activity with time only.
        return String(try await client.createActivity(name: log.title, sportType: "Run", start: log.startedAt,
                                                      elapsedSeconds: Int(log.durationSeconds), description: description))
    }

    func upload(strength log: StrengthLogModel, units: UnitSystem) async throws -> String {
        guard let client else { throw StravaError.notConnected }
        let elapsed = Int(max(log.durationSeconds, (log.finishedAt ?? log.startedAt).timeIntervalSince(log.startedAt)))
        return String(try await client.createActivity(name: log.title.isEmpty ? "Strength" : log.title, sportType: "WeightTraining",
                                                      start: log.startedAt, elapsedSeconds: elapsed,
                                                      description: Self.strengthDescription(log, units: units)))
    }

    static func runDescription(_ log: RunLogModel) -> String {
        var parts = ["Planned and coached by Kinetix."]
        if log.targetedSeconds > 0 {
            parts.append("\(Int((log.timeInTargetSeconds / log.targetedSeconds * 100).rounded()))% of target time on pace.")
        }
        if log.effort > 0 { parts.append("Effort \(Int(log.effort))/10.") }
        return parts.joined(separator: " ")
    }

    /// "Back Squat: 3 × 5 @ 100 kg" for each exercise.
    static func strengthDescription(_ log: StrengthLogModel, units: UnitSystem) -> String {
        let format = DisplayFormat(units: units)
        let sets = log.orderedSets.filter(\.isCompleted)
        var lines: [String] = []
        var seen: [String] = []
        for key in sets.map(\.progressionKey) where !seen.contains(key) { seen.append(key) }
        for key in seen {
            let exerciseSets = sets.filter { $0.progressionKey == key }
            guard let first = exerciseSets.first else { continue }
            let reps = exerciseSets.map { String($0.actualReps) }
            let sameReps = Set(reps).count == 1
            let repText = sameReps ? "\(exerciseSets.count) × \(reps[0])" : reps.joined(separator: ", ")
            let heaviest = exerciseSets.map(\.actualWeightKg).max() ?? 0
            let name = first.exerciseName.isEmpty ? first.exerciseId : first.exerciseName
            lines.append(first.isBodyweight || heaviest == 0 ? "\(name): \(repText)" : "\(name): \(repText) @ \(format.weight(heaviest))")
        }
        lines.append("Planned and tracked by Kinetix.")
        return lines.joined(separator: "\n")
    }
}

/// Decides what to bring in from Strava.
enum StravaImport {
    struct Plan {
        /// Runs to add to Kinetix's history.
        var runs: [StravaActivity] = []
        /// Everything else, for training load.
        var workouts: [ExternalWorkout] = []
    }

    /// Skips Kinetix's own uploads, activities Kinetix already has (by id), and anything
    /// that overlaps a session recorded in Kinetix (the same training, recorded twice).
    static func plan(activities: [StravaActivity], knownActivityIds: Set<String>, kinetixSessions: [DateInterval]) -> Plan {
        var plan = Plan()
        for activity in activities {
            guard !activity.isFromKinetix, !knownActivityIds.contains(String(activity.id)), activity.elapsedTime >= 60 else { continue }
            let interval = DateInterval(start: activity.startDate, end: max(activity.startDate, activity.endDate))
            let overlapsKinetix = kinetixSessions.contains { other in
                guard let overlap = interval.intersection(with: other) else { return false }
                let shorter = min(interval.duration, other.duration)
                return shorter > 0 && overlap.duration / shorter >= 0.5
            }
            guard !overlapsKinetix else { continue }
            if activity.category == .run {
                plan.runs.append(activity)
            } else {
                plan.workouts.append(ExternalWorkout(id: stableID(for: activity.id), start: activity.startDate, end: activity.endDate,
                                                     kind: kind(for: activity.category), name: name(for: activity),
                                                     distanceMeters: activity.distance > 0 ? activity.distance : nil,
                                                     averageHeartRate: activity.averageHeartrate))
            }
        }
        return plan
    }

    /// The same Strava activity always gets the same id (so re-imports replace, not add).
    static func stableID(for activityId: Int) -> UUID {
        UUID(uuidString: String(format: "57524156-0000-0000-0000-%012llx", UInt64(truncatingIfNeeded: activityId) & 0xFFFF_FFFF_FFFF)) ?? UUID()
    }

    private static func kind(for category: StravaActivity.Category) -> ExternalWorkout.Kind {
        switch category {
        case .run: return .run
        case .strength: return .strength
        case .cycling: return .cycling
        case .walking: return .walking
        case .other: return .other
        }
    }

    private static func name(for activity: StravaActivity) -> String {
        activity.name.isEmpty ? activity.sportType : activity.name
    }
}

extension RunLogModel {
    /// When the run happened (for spotting the same run recorded twice).
    var interval: DateInterval {
        DateInterval(start: startedAt, duration: max(durationSeconds, (finishedAt ?? startedAt).timeIntervalSince(startedAt)))
    }
}

extension StrengthLogModel {
    var interval: DateInterval {
        DateInterval(start: startedAt, duration: max(durationSeconds, (finishedAt ?? startedAt).timeIntervalSince(startedAt)))
    }
}
