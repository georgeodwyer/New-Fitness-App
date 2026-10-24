import Foundation
import TrainingEngine

/// The watch gesture settings, kept on the iPhone and sent to the watch with the plan.
@MainActor
enum WatchControlsStore {
    static let key = "watch.controls"
    /// What the watch last said about itself (`WatchDeviceInfo`).
    static let deviceKey = "watch.deviceInfo"

    static var settings: WatchControlSettings {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(WatchControlSettings.self, from: $0) } ?? .standard }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
            WatchSyncService.shared.sendPlan()
        }
    }

    static var device: WatchDeviceInfo? {
        UserDefaults.standard.data(forKey: deviceKey).flatMap(WatchDeviceInfo.decode)
    }
}
