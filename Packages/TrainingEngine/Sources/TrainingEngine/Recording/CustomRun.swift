import Foundation

/// The kinds of run you can record without a plan.
public enum RecordRunType: String, Codable, CaseIterable, Sendable {
    case free, easy, recovery, long, tempo, intervals, progression, fartlek

    public var displayName: String {
        switch self {
        case .free: return "Free run"
        case .easy: return "Easy"
        case .recovery: return "Recovery"
        case .long: return "Long run"
        case .tempo: return "Tempo / Threshold"
        case .intervals: return "Intervals"
        case .progression: return "Progression"
        case .fartlek: return "Fartlek"
        }
    }

    public var detail: String {
        switch self {
        case .free: return "Just run. No targets, splits and voice updates only."
        case .easy: return "Steady and conversational."
        case .recovery: return "Very easy, short. Helps you absorb hard days."
        case .long: return "Your longest run of the week, at easy pace."
        case .tempo: return "Comfortably hard blocks at threshold pace."
        case .intervals: return "Fast repeats with recoveries."
        case .progression: return "Start easy, finish strong."
        case .fartlek: return "Playful surges of speed."
        }
    }

    /// The planned-session type it corresponds to (nil for a free run).
    public var sessionType: RunSessionType? {
        switch self {
        case .free: return nil
        case .easy, .fartlek: return .easy
        case .recovery: return .recovery
        case .long: return .long
        case .tempo, .progression: return .tempo
        case .intervals: return .intervals
        }
    }

    /// Pre-filled effort (1–10) for the end-of-run question.
    public var typicalEffort: Double {
        switch self {
        case .free, .easy: return 4
        case .recovery: return 2
        case .long: return 5
        case .tempo, .progression: return 7
        case .intervals: return 8
        case .fartlek: return 6
        }
    }
}

/// A pace target: a single pace (the coaching tolerance applies either side) or a range.
public enum PaceTarget: Codable, Equatable, Hashable, Sendable {
    case single(Pace)
    case range(PaceRange)

    public var range: PaceRange {
        switch self {
        case .single(let pace): return PaceRange(fastest: pace, slowest: pace)
        case .range(let range): return range
        }
    }

    public var middle: Pace {
        let range = self.range
        return Pace(secondsPerKm: (range.fastest.secondsPerKm + range.slowest.secondsPerKm) / 2)
    }

    /// "4:15/km" or "4:10–4:20/km".
    public func formatted(_ units: UnitSystem) -> String {
        switch self {
        case .single(let pace):
            return Units.formatPace(pace, units: units) + Units.paceUnitLabel(units)
        case .range(let range):
            return Units.formatPace(range.fastest, units: units) + "–" + Units.formatPace(range.slowest, units: units)
                + Units.paceUnitLabel(units)
        }
    }
}

/// One step of a custom workout: e.g. "10 min at 4:15/km".
public struct WorkoutStep: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: SegmentKind
    public var length: SegmentLength
    public var target: PaceTarget?

    public init(id: UUID = UUID(), kind: SegmentKind, length: SegmentLength, target: PaceTarget? = nil) {
        self.id = id
        self.kind = kind
        self.length = length
        self.target = target
    }
}

/// Steps run `repeats` times in a row (1 for a single warm-up or steady block).
public struct WorkoutBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var repeats: Int
    public var steps: [WorkoutStep]

    public init(id: UUID = UUID(), repeats: Int = 1, steps: [WorkoutStep]) {
        self.id = id
        self.repeats = max(1, repeats)
        self.steps = steps
    }
}

/// A run the athlete builds themselves (and can save as a template).
public struct CustomRunWorkout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var type: RecordRunType
    public var blocks: [WorkoutBlock]

    public init(id: UUID = UUID(), name: String, type: RecordRunType, blocks: [WorkoutBlock] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.blocks = blocks
    }

    /// Segments for the run engine (nil for an unstructured run).
    public var structure: RunStructure? {
        var segments: [RunSegment] = []
        for block in blocks where block.repeats > 0 {
            let workSteps = block.steps.filter { $0.kind == .work }.count
            for rep in 1...block.repeats {
                for step in block.steps {
                    var label: String?
                    if block.repeats > 1 && step.kind == .work && workSteps == 1 {
                        label = "Rep \(rep) of \(block.repeats)"
                    }
                    segments.append(RunSegment(kind: step.kind, length: step.length, targetPace: step.target?.range, label: label))
                }
            }
        }
        // Drop a trailing recovery straight before a cool-down or the end: it adds nothing.
        if let last = segments.last, last.kind == .recovery { segments.removeLast() }
        return segments.isEmpty ? nil : RunStructure(segments: segments)
    }

    /// Rough total distance and time, using each step's target pace (or `defaultPace`).
    public func estimate(defaultPace: Pace) -> RunEstimate {
        var distance = 0.0, duration = 0.0
        for block in blocks {
            for step in block.steps {
                let pace = step.target?.middle ?? defaultPace
                switch step.length {
                case .distance(let meters):
                    distance += meters * Double(block.repeats)
                    duration += meters / 1000 * pace.secondsPerKm * Double(block.repeats)
                case .duration(let seconds):
                    duration += seconds * Double(block.repeats)
                    distance += seconds / pace.secondsPerKm * 1000 * Double(block.repeats)
                }
            }
        }
        return RunEstimate(distanceMeters: distance, durationSeconds: duration)
    }

    /// "2 km warm-up · 2 × (10 min @ 4:15/km, 2 min easy) · 2 km cool-down".
    public func summary(units: UnitSystem) -> String {
        guard !blocks.isEmpty else { return type == .free ? "No targets" : "No steps yet" }
        return blocks.map { block in
            let steps = block.steps.map { Self.describe($0, units: units) }
            if block.repeats > 1 {
                let inner = steps.count == 1 ? steps[0] : "(" + steps.joined(separator: ", ") + ")"
                return "\(block.repeats) × \(inner)"
            }
            return steps.joined(separator: " · ")
        }.joined(separator: " · ")
    }

    public static func describe(_ step: WorkoutStep, units: UnitSystem) -> String {
        let length = describe(step.length, units: units)
        let pace = step.target.map { " @ " + $0.formatted(units) } ?? ""
        switch step.kind {
        case .warmUp: return "\(length) warm-up\(pace)"
        case .coolDown: return "\(length) cool-down\(pace)"
        case .recovery: return step.target == nil ? "\(length) easy" : "\(length) recovery\(pace)"
        case .work, .steady: return length + pace
        }
    }

    public static func describe(_ length: SegmentLength, units: UnitSystem) -> String {
        switch length {
        case .duration(let seconds):
            if seconds >= 60 && Int(seconds) % 60 == 0 { return "\(Int(seconds) / 60) min" }
            if seconds >= 60 { return Units.formatMinutesSeconds(seconds) }
            return "\(Int(seconds)) s"
        case .distance(let meters):
            if units == .metric && meters < 1000 { return "\(Int(meters)) m" }
            let value = Units.distance(meters: meters, in: units)
            let text = value == value.rounded() ? String(Int(value)) : String((value * 100).rounded() / 100)
            return "\(text) \(Units.distanceUnitLabel(units))"
        }
    }
}

extension CustomRunWorkout {
    /// A sensible starting workout for each type, using the athlete's pace zones when known.
    /// Everything can be edited before starting.
    public static func starter(for type: RecordRunType, zones: PaceZones?) -> CustomRunWorkout {
        func pace(_ zone: PaceZone) -> PaceTarget? {
            guard let zones else { return nil }
            let typical = zones.typicalPace(for: zone)
            // Round to 5 s so it's easy to read and edit.
            return .single(Pace(secondsPerKm: (typical.secondsPerKm / 5).rounded() * 5))
        }
        func step(_ kind: SegmentKind, km: Double, _ target: PaceTarget? = nil) -> WorkoutStep {
            WorkoutStep(kind: kind, length: .distance(meters: km * 1000), target: target)
        }
        func step(_ kind: SegmentKind, minutes: Double, _ target: PaceTarget? = nil) -> WorkoutStep {
            WorkoutStep(kind: kind, length: .duration(seconds: minutes * 60), target: target)
        }
        let blocks: [WorkoutBlock]
        switch type {
        case .free:
            blocks = []
        case .easy:
            blocks = [WorkoutBlock(steps: [step(.steady, km: 6, pace(.easy))])]
        case .recovery:
            blocks = [WorkoutBlock(steps: [step(.steady, minutes: 30, nil)])]
        case .long:
            blocks = [WorkoutBlock(steps: [step(.steady, km: 15, pace(.easy))])]
        case .tempo:
            blocks = [
                WorkoutBlock(steps: [step(.warmUp, km: 2)]),
                WorkoutBlock(repeats: 2, steps: [step(.work, minutes: 10, pace(.threshold)), step(.recovery, minutes: 2)]),
                WorkoutBlock(steps: [step(.coolDown, km: 2)])
            ]
        case .intervals:
            blocks = [
                WorkoutBlock(steps: [step(.warmUp, km: 2)]),
                WorkoutBlock(repeats: 6, steps: [step(.work, km: 0.8, pace(.interval)), step(.recovery, minutes: 1.5)]),
                WorkoutBlock(steps: [step(.coolDown, km: 2)])
            ]
        case .progression:
            blocks = [WorkoutBlock(steps: [
                step(.steady, km: 3, pace(.easy)),
                step(.steady, km: 3, pace(.marathon)),
                step(.work, km: 2, pace(.threshold))
            ])]
        case .fartlek:
            blocks = [
                WorkoutBlock(steps: [step(.warmUp, minutes: 10)]),
                WorkoutBlock(repeats: 8, steps: [step(.work, minutes: 1, pace(.interval)), step(.recovery, minutes: 1)]),
                WorkoutBlock(steps: [step(.coolDown, minutes: 10)])
            ]
        }
        return CustomRunWorkout(name: type.displayName, type: type, blocks: blocks)
    }
}
