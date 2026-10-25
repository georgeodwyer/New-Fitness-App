import Foundation
import TrainingEngine

/// Unit-aware display strings. Data is stored in metres, seconds and kilograms.
struct DisplayFormat {
    var units: UnitSystem

    func pace(_ pace: Pace) -> String {
        Units.formatPace(pace, units: units) + Units.paceUnitLabel(units)
    }

    func paceRange(_ range: PaceRange) -> String {
        "\(Units.formatPace(range.fastest, units: units))–\(Units.formatPace(range.slowest, units: units))\(Units.paceUnitLabel(units))"
    }

    func distance(_ meters: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", Units.distance(meters: meters, in: units)) + " " + Units.distanceUnitLabel(units)
    }

    /// Short distances for directions: "80 m" / "90 yd", or km/mi once over 1 km.
    func shortDistance(_ meters: Double) -> String {
        guard meters < 1000 else { return distance(meters) }
        switch units {
        case .metric: return "\(Int((meters / 10).rounded() * 10)) m"
        case .imperial: return "\(Int((meters * 1.09361 / 10).rounded() * 10)) yd"
        }
    }

    func weight(_ kg: Double) -> String {
        Units.formatWeight(kg: kg, units: units) + " " + Units.weightUnitLabel(units)
    }

    /// A set's weight, or "pick a weight" for a machine they haven't used yet (0).
    func load(_ kg: Double) -> String { kg > 0 ? weight(kg) : "pick a weight" }

    /// "60 kg × 8", or "8 reps · pick a weight" before they've chosen one.
    func set(weightKg: Double, reps: Int) -> String {
        weightKg > 0 ? "\(weight(weightKg)) × \(reps)" : "\(reps) reps · pick a weight"
    }

    func segmentLength(_ length: SegmentLength) -> String {
        switch length {
        case .distance(let meters):
            if units == .metric && meters < 1000 { return "\(Int(meters)) m" }
            return distance(meters, decimals: meters.truncatingRemainder(dividingBy: 1000) == 0 && units == .metric ? 0 : 1)
        case .duration(let seconds):
            if seconds < 60 { return "\(Int(seconds)) s" }
            return Units.formatMinutesSeconds(seconds) + " min"
        }
    }
}

extension SegmentKind {
    var displayName: String {
        switch self {
        case .warmUp: return "Warm-up"
        case .work: return "Work"
        case .recovery: return "Recovery"
        case .coolDown: return "Cool-down"
        case .steady: return "Steady"
        }
    }
}

extension TrainingPhase {
    var explanation: String {
        switch self {
        case .base: return "Aerobic base: mostly easy running and steady strength work."
        case .build: return "Harder sessions and rising volume."
        case .peak: return "Your most specific training; volume held."
        case .taper: return "Volume drops so you arrive fresh."
        }
    }
}
