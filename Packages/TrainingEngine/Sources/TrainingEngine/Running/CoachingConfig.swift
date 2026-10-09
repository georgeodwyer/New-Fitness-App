import Foundation

/// The runner's audio-coaching preferences.
public struct CoachingConfig: Codable, Equatable, Sendable {
    /// Seconds continuously off pace before a cue (and again before any repeat).
    public var paceCueDelaySeconds: Double
    /// How far outside the target range (sec/km) still counts as on pace.
    public var toleranceSecondsPerKm: Double
    public var paceCuesEnabled: Bool
    public var splitAnnouncementsEnabled: Bool
    public var segmentAnnouncementsEnabled: Bool
    public var cuesDuringWarmUpCoolDown: Bool
    public var units: UnitSystem
    /// Rolling window used to smooth GPS pace.
    public var smoothingWindowSeconds: Double

    public init(
        paceCueDelaySeconds: Double = 20,
        toleranceSecondsPerKm: Double = 10,
        paceCuesEnabled: Bool = true,
        splitAnnouncementsEnabled: Bool = true,
        segmentAnnouncementsEnabled: Bool = true,
        cuesDuringWarmUpCoolDown: Bool = false,
        units: UnitSystem = .metric,
        smoothingWindowSeconds: Double = 20
    ) {
        self.paceCueDelaySeconds = paceCueDelaySeconds
        self.toleranceSecondsPerKm = toleranceSecondsPerKm
        self.paceCuesEnabled = paceCuesEnabled
        self.splitAnnouncementsEnabled = splitAnnouncementsEnabled
        self.segmentAnnouncementsEnabled = segmentAnnouncementsEnabled
        self.cuesDuringWarmUpCoolDown = cuesDuringWarmUpCoolDown
        self.units = units
        self.smoothingWindowSeconds = smoothingWindowSeconds
    }
}
