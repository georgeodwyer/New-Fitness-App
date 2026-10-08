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

    func weight(_ kg: Double) -> String {
        Units.formatWeight(kg: kg, units: units) + " " + Units.weightUnitLabel(units)
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
