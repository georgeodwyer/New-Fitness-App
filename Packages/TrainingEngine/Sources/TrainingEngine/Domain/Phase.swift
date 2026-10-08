import Foundation

/// Periodisation phase of a training block.
public enum TrainingPhase: String, Codable, CaseIterable, Sendable {
    /// Aerobic base: mostly easy running, gentle volume increases.
    case base
    /// More quality work, volume climbing towards peak.
    case build
    /// Highest specific work, volume held.
    case peak
    /// Volume cut before the event so you arrive fresh.
    case taper

    public var displayName: String {
        switch self {
        case .base: return "Base"
        case .build: return "Build"
        case .peak: return "Peak"
        case .taper: return "Taper"
        }
    }
}
