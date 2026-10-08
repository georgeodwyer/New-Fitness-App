import Foundation
import SwiftData

/// Audio coaching preferences for runs.
@Model
final class CoachingSettingsModel: SyncTracked {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var needsSync: Bool

    /// Seconds continuously off pace before a cue is spoken.
    var paceCueDelaySeconds: Double
    /// How far outside the target range (sec/km) still counts as on pace.
    var paceToleranceSecondsPerKm: Double
    var voiceIdentifier: String?
    /// 0...1
    var cueVolume: Double
    var paceCuesEnabled: Bool
    var splitAnnouncementsEnabled: Bool
    var segmentAnnouncementsEnabled: Bool
    var cuesDuringWarmUpCoolDown: Bool

    init(id: UUID = UUID(), now: Date = .now) {
        self.id = id
        self.updatedAt = now
        self.deletedAt = nil
        self.needsSync = true
        self.paceCueDelaySeconds = 20
        self.paceToleranceSecondsPerKm = 10
        self.voiceIdentifier = nil
        self.cueVolume = 1
        self.paceCuesEnabled = true
        self.splitAnnouncementsEnabled = true
        self.segmentAnnouncementsEnabled = true
        self.cuesDuringWarmUpCoolDown = false
    }
}
