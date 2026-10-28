import Foundation
import Observation
import SwiftData
import KinetixSync
import TrainingEngine

/// Strava connection (tokens kept in the Keychain on this iPhone) and activity uploads.
/// Kinetix only sends to Strava: activities recorded elsewhere come in through Apple Health.
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

    // MARK: - Strava data

    /// Kinetix only sends activities to Strava; it doesn't keep Strava's data (Strava's API
    /// policy from June 2026 limits that). Activities brought in by earlier versions are
    /// removed (also when one arrives by sync from a device still on an older version).
    /// Workouts recorded elsewhere reach Kinetix through Apple Health instead.
    func removeImportedActivities(in context: ModelContext, settings: IntegrationSettings = .shared) {
        let runs = (try? context.fetch(FetchDescriptor<RunLogModel>(predicate: #Predicate { $0.importSourceRaw == "strava" && $0.deletedAt == nil }))) ?? []
        for run in runs { run.softDelete() }
        if !settings.stravaWorkouts.isEmpty { settings.stravaWorkouts = [] }
        if settings.stravaLastImport != nil { settings.stravaLastImport = nil }
        if !runs.isEmpty {
            try? context.save()
            SyncService.shared.requestSync()
        }
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
