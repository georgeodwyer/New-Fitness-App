import SwiftUI

/// Type scale. Built on system text styles so everything scales with Dynamic Type.
/// Swap `design` (or move to a custom font with `relativeTo:`) once the Stitch
/// export confirms the typeface.
enum KXFont {
    /// Big screen headline: "Calibrate your Hybrid Engine", "Welcome back".
    static let display = Font.system(.largeTitle, design: .default, weight: .bold)
    /// Screen title in the header bar: "Dashboard", "Running Trainer".
    static let title = Font.system(.title2, design: .default, weight: .bold)
    /// Card titles: "Barbell Back Squat", "Today's Schedule".
    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body)
    static let bodyEmphasis = Font.system(.body, weight: .semibold)
    static let callout = Font.system(.subheadline)
    static let caption = Font.system(.caption)
    static let captionEmphasis = Font.system(.caption, weight: .semibold)
    /// Tiny uppercase labels: "LIVE TELEMETRY HUD", "SESSION A".
    static let overline = Font.system(.caption2, weight: .bold)
    /// Large live numbers: "4:42", "105.0".
    static let metric = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    /// Medium numbers inside tiles: "28.4", "158".
    static let metricSmall = Font.system(.title2, design: .rounded, weight: .bold).monospacedDigit()
}
