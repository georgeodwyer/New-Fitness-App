import Foundation

/// Estimated distance and duration of a structured run at the runner's paces.
public struct RunEstimate: Equatable, Sendable {
    public var distanceMeters: Double
    public var durationSeconds: Double
}

extension RunStructure {
    /// Estimates distance and time, assuming segments without a target run at easy pace.
    public func estimate(zones: PaceZones) -> RunEstimate {
        var distance = 0.0
        var duration = 0.0
        let easy = zones.typicalPace(for: .easy)
        for segment in segments {
            let pace: Pace
            if let target = segment.targetPace {
                pace = Pace(secondsPerKm: (target.fastest.secondsPerKm + target.slowest.secondsPerKm) / 2)
            } else {
                pace = easy
            }
            switch segment.length {
            case .distance(let meters):
                distance += meters
                duration += meters / 1000 * pace.secondsPerKm
            case .duration(let seconds):
                duration += seconds
                distance += seconds / pace.secondsPerKm * 1000
            }
        }
        return RunEstimate(distanceMeters: distance, durationSeconds: duration)
    }
}

enum RunBuilder {
    /// A structured quality run from a template.
    static func structure(from template: RunWorkoutTemplate, zones: PaceZones) -> RunStructure {
        var segments: [RunSegment] = []
        if template.warmUpMinutes > 0 {
            segments.append(RunSegment(kind: .warmUp, length: .duration(seconds: template.warmUpMinutes * 60), targetPace: zones.range(for: .easy), label: "Warm-up"))
        }
        for block in template.blocks {
            for rep in 0..<max(block.repeats, 1) {
                let label = block.repeats > 1 ? "Rep \(rep + 1) of \(block.repeats)" : "Main set"
                segments.append(segment(from: block.work, kind: .work, zones: zones, label: label))
                if let recovery = block.recovery, rep < block.repeats - 1 {
                    segments.append(segment(from: recovery, kind: .recovery, zones: zones, label: "Recovery jog"))
                }
            }
        }
        if template.coolDownMinutes > 0 {
            segments.append(RunSegment(kind: .coolDown, length: .duration(seconds: template.coolDownMinutes * 60), targetPace: zones.range(for: .easy), label: "Cool-down"))
        }
        return RunStructure(segments: segments)
    }

    /// A continuous run (easy, recovery or long) of a given distance.
    static func steady(_ type: RunSessionType, distanceMeters: Double, zones: PaceZones) -> RunStructure {
        var range = zones.range(for: .easy)
        if type == .recovery {
            // Recovery runs sit at the slow end of easy.
            range = PaceRange(fastest: range.slowest, slowest: Pace(secondsPerKm: range.slowest.secondsPerKm + 30))
        }
        let label: String
        switch type {
        case .long: label = "Long run"
        case .recovery: label = "Recovery run"
        default: label = "Easy run"
        }
        return RunStructure(segments: [
            RunSegment(kind: .steady, length: .distance(meters: distanceMeters), targetPace: range, label: label)
        ])
    }

    private static func segment(from spec: SegmentSpec, kind: SegmentKind, zones: PaceZones, label: String) -> RunSegment {
        let length: SegmentLength
        if let meters = spec.distanceMeters {
            length = .distance(meters: meters)
        } else {
            length = .duration(seconds: spec.durationSeconds ?? 60)
        }
        return RunSegment(kind: kind, length: length, targetPace: zones.range(for: spec.zone), label: label)
    }

    /// Rounds a distance to a tidy value (nearest 500 m).
    static func tidy(_ meters: Double) -> Double {
        (meters / 500).rounded() * 500
    }
}
