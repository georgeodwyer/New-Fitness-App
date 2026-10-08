import Foundation

/// Conversions and display formatting. Internally the app always stores
/// metres, seconds and kilograms; units only change what the user sees.
public enum Units {
    public static let metersPerMile = 1609.344
    public static let poundsPerKg = 2.2046226218

    public static func kgToLb(_ kg: Double) -> Double { kg * poundsPerKg }
    public static func lbToKg(_ lb: Double) -> Double { lb / poundsPerKg }

    /// Distance in km or miles.
    public static func distance(meters: Double, in units: UnitSystem) -> Double {
        units == .metric ? meters / 1000 : meters / metersPerMile
    }

    public static func distanceUnitLabel(_ units: UnitSystem) -> String {
        units == .metric ? "km" : "mi"
    }

    public static func weightUnitLabel(_ units: UnitSystem) -> String {
        units == .metric ? "kg" : "lb"
    }

    public static func paceUnitLabel(_ units: UnitSystem) -> String {
        units == .metric ? "/km" : "/mi"
    }

    /// "4:42" style pace (no unit).
    public static func formatPace(_ pace: Pace, units: UnitSystem) -> String {
        formatMinutesSeconds(pace.seconds(per: units))
    }

    /// "4:42" for 282 seconds; "1:02:05" once over an hour.
    public static func formatMinutesSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Distance with sensible precision: "4.82".
    public static func formatDistance(meters: Double, units: UnitSystem) -> String {
        String(format: "%.2f", distance(meters: meters, in: units))
    }

    /// Weight for display: whole numbers when exact, else one decimal ("105", "102.5").
    public static func formatWeight(kg: Double, units: UnitSystem) -> String {
        let value = units == .metric ? kg : kgToLb(kg)
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        return String(format: "%.1f", rounded)
    }
}
