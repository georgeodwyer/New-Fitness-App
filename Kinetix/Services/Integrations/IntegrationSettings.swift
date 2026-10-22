import Foundation
import Observation
import TrainingEngine

/// Per-device integration choices (Apple Health, heart rate strap, Strava). These belong
/// to this iPhone rather than the account, so they live in UserDefaults and aren't synced.
@Observable
@MainActor
final class IntegrationSettings {
    static let shared = IntegrationSettings()

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        healthEnabled = defaults.bool(forKey: Keys.healthEnabled)
        healthConnectedAt = defaults.object(forKey: Keys.healthConnectedAt) as? Date
        heartRateSensorID = defaults.string(forKey: Keys.sensorID).flatMap(UUID.init(uuidString:))
        heartRateSensorName = defaults.string(forKey: Keys.sensorName)
        useWatchHeartRate = defaults.object(forKey: Keys.useWatchHeartRate) as? Bool ?? true
        mirrorRunsToWatch = defaults.object(forKey: Keys.mirrorRuns) as? Bool ?? true
        runHeartRateSource = defaults.string(forKey: Keys.runHeartRateSource).flatMap(RunHeartRateSource.init(rawValue:)) ?? .watch
        stravaUploadRuns = defaults.object(forKey: Keys.stravaRuns) as? Bool ?? true
        stravaUploadLifts = defaults.object(forKey: Keys.stravaLifts) as? Bool ?? false
        stravaConnectedAt = defaults.object(forKey: Keys.stravaConnectedAt) as? Date
        stravaImportEnabled = defaults.object(forKey: Keys.stravaImport) as? Bool ?? true
        stravaLastImport = defaults.object(forKey: Keys.stravaLastImport) as? Date
        stravaWorkouts = defaults.data(forKey: Keys.stravaWorkouts)
            .flatMap { try? JSONDecoder().decode([ExternalWorkout].self, from: $0) } ?? []
        externalWorkouts = defaults.data(forKey: Keys.externalWorkouts)
            .flatMap { try? JSONDecoder().decode([ExternalWorkout].self, from: $0) } ?? []
        uploadFailures = defaults.dictionary(forKey: Keys.uploadFailures) as? [String: String] ?? [:]
    }

    private enum Keys {
        static let healthEnabled = "integrations.health.enabled"
        static let healthConnectedAt = "integrations.health.connectedAt"
        static let sensorID = "integrations.hr.sensorID"
        static let sensorName = "integrations.hr.sensorName"
        static let useWatchHeartRate = "integrations.hr.useWatch"
        static let mirrorRuns = "integrations.watch.mirrorRuns"
        static let runHeartRateSource = "integrations.hr.runSource"
        static let stravaRuns = "integrations.strava.uploadRuns"
        static let stravaLifts = "integrations.strava.uploadLifts"
        static let stravaConnectedAt = "integrations.strava.connectedAt"
        static let stravaImport = "integrations.strava.import"
        static let stravaLastImport = "integrations.strava.lastImport"
        static let stravaWorkouts = "integrations.strava.workouts"
        static let externalWorkouts = "integrations.health.externalWorkouts"
        static let uploadFailures = "integrations.uploadFailures"
    }

    /// Save finished sessions to Apple Health and read heart rate and other workouts.
    var healthEnabled: Bool { didSet { defaults.set(healthEnabled, forKey: Keys.healthEnabled) } }
    /// Only sessions finished after this are saved automatically (no back-filling surprises).
    var healthConnectedAt: Date? { didSet { defaults.set(healthConnectedAt, forKey: Keys.healthConnectedAt) } }

    /// The paired Bluetooth heart rate strap.
    var heartRateSensorID: UUID? { didSet { defaults.set(heartRateSensorID?.uuidString, forKey: Keys.sensorID) } }
    var heartRateSensorName: String? { didSet { defaults.set(heartRateSensorName, forKey: Keys.sensorName) } }
    /// Use heart rate from Apple Watch (through Apple Health) during runs.
    var useWatchHeartRate: Bool { didSet { defaults.set(useWatchHeartRate, forKey: Keys.useWatchHeartRate) } }
    /// Open the Kinetix watch app and show the run there when a run starts on the phone.
    var mirrorRunsToWatch: Bool { didSet { defaults.set(mirrorRunsToWatch, forKey: Keys.mirrorRuns) } }
    /// The last answer to "Heart rate from?" (asked when both a strap and the watch could be used).
    var runHeartRateSource: RunHeartRateSource { didSet { defaults.set(runHeartRateSource.rawValue, forKey: Keys.runHeartRateSource) } }

    var stravaUploadRuns: Bool { didSet { defaults.set(stravaUploadRuns, forKey: Keys.stravaRuns) } }
    var stravaUploadLifts: Bool { didSet { defaults.set(stravaUploadLifts, forKey: Keys.stravaLifts) } }
    var stravaConnectedAt: Date? { didSet { defaults.set(stravaConnectedAt, forKey: Keys.stravaConnectedAt) } }
    /// Bring in activities recorded elsewhere (runs into history, everything into load).
    var stravaImportEnabled: Bool { didSet { defaults.set(stravaImportEnabled, forKey: Keys.stravaImport) } }
    /// When Strava was last checked for new activities.
    var stravaLastImport: Date? { didSet { defaults.set(stravaLastImport, forKey: Keys.stravaLastImport) } }
    /// Non-run activities from Strava (last 4 weeks), counted in training load.
    var stravaWorkouts: [ExternalWorkout] {
        didSet { defaults.set(try? JSONEncoder().encode(stravaWorkouts), forKey: Keys.stravaWorkouts) }
    }

    /// Other apps' workouts that count towards training load: Apple Health's and Strava's,
    /// with the same workout seen in both counted once.
    var loadWorkouts: [ExternalWorkout] {
        ExternalWorkouts.merged(healthEnabled ? externalWorkouts : [], stravaImportEnabled ? stravaWorkouts : [])
    }

    /// Workouts from other apps (last 4 weeks), refreshed from Apple Health.
    var externalWorkouts: [ExternalWorkout] {
        didSet { defaults.set(try? JSONEncoder().encode(externalWorkouts), forKey: Keys.externalWorkouts) }
    }

    /// Uploads that failed for a reason retrying won't fix, keyed "strava.<log id>" → message.
    var uploadFailures: [String: String] { didSet { defaults.set(uploadFailures, forKey: Keys.uploadFailures) } }

    /// Forget everything (used when deleting all data).
    func reset() {
        HealthDataConsent.withdraw()
        healthEnabled = false
        healthConnectedAt = nil
        heartRateSensorID = nil
        heartRateSensorName = nil
        useWatchHeartRate = true
        mirrorRunsToWatch = true
        runHeartRateSource = .watch
        stravaUploadRuns = true
        stravaUploadLifts = false
        stravaConnectedAt = nil
        stravaImportEnabled = true
        stravaLastImport = nil
        stravaWorkouts = []
        externalWorkouts = []
        uploadFailures = [:]
    }
}

/// Where heart rate comes from during a run on the phone.
enum RunHeartRateSource: String {
    /// Apple Watch (live from the mirrored run, or through Apple Health).
    case watch
    /// The paired Bluetooth chest strap.
    case strap
}
