import Foundation

/// Builds the spoken phrases. Written to sound natural through text-to-speech.
public enum Announcer {
    public static func paceText(_ pace: Pace, units: UnitSystem) -> String {
        Units.formatPace(pace, units: units)
    }

    static func perUnit(_ units: UnitSystem) -> String {
        units == .metric ? "per kilometre" : "per mile"
    }

    static func rangeText(_ range: PaceRange, units: UnitSystem) -> String {
        "\(paceText(range.fastest, units: units)) to \(paceText(range.slowest, units: units)) \(perUnit(units))"
    }

    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) seconds" }
        let minutes = total / 60, rest = total % 60
        let m = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return rest == 0 ? m : "\(m) \(rest) seconds"
    }

    static func distanceText(_ meters: Double, units: UnitSystem) -> String {
        if units == .metric {
            if meters < 1000 { return "\(Int(meters.rounded())) metres" }
            let km = meters / 1000
            return km == km.rounded() ? "\(Int(km)) kilometre\(km == 1 ? "" : "s")" : String(format: "%.1f kilometres", km)
        }
        let miles = meters / Units.metersPerMile
        if miles < 0.5 { return "\(Int((meters * 1.0936).rounded())) yards" }
        return miles == miles.rounded() ? "\(Int(miles)) mile\(miles == 1 ? "" : "s")" : String(format: "%.1f miles", miles)
    }

    static func lengthText(_ length: SegmentLength, units: UnitSystem) -> String {
        switch length {
        case .duration(let seconds): return durationText(seconds)
        case .distance(let meters): return distanceText(meters, units: units)
        }
    }

    public static func segmentStart(_ segment: RunSegment, units: UnitSystem) -> String {
        let length = lengthText(segment.length, units: units)
        let target = segment.targetPace.map { " at \(rangeText($0, units: units))" } ?? ""
        switch segment.kind {
        case .warmUp: return "Warm-up. \(length) easy."
        case .coolDown: return "Cool-down. \(length) easy. Nice work."
        case .recovery: return "Recovery jog. \(length), nice and easy."
        case .work: return "\(segment.label ?? "Main set"). \(length)\(target). Go."
        case .steady: return "\(segment.label ?? "Run"). \(length)\(target)."
        }
    }

    public static func paceCue(_ direction: PaceRange.Position, target: PaceRange, units: UnitSystem) -> String {
        let goal = "Target \(rangeText(target, units: units))."
        switch direction {
        case .tooFast: return "Ease off, you're running too fast. \(goal)"
        case .tooSlow: return "Pick it up, you're running too slow. \(goal)"
        case .onTarget: return "On pace."
        }
    }

    public static func split(_ split: Split, units: UnitSystem) -> String {
        let unit = units == .metric ? "Kilometre" : "Mile"
        return "\(unit) \(split.index). \(Units.formatMinutesSeconds(split.durationSeconds)). Average pace \(paceText(split.averagePace, units: units)) \(perUnit(units))."
    }

    public static let workoutComplete = "Workout complete. Great work. Keep moving to cool down, or finish your run."
}
