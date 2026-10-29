import Foundation

/// The kinds of run you can record without a plan.
public enum RecordRunType: String, Codable, CaseIterable, Sendable {
    case free, easy, recovery, long, tempo, intervals, progression, fartlek, race

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
        case .race: return "Race"
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
        case .race: return "Race a distance. A new best updates your paces and plan."
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
        case .race: return .tempo
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
        case .race: return 9
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
public struct RunBlock: Codable, Equatable, Identifiable, Sendable {
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
    public var blocks: [RunBlock]

    public init(id: UUID = UUID(), name: String, type: RecordRunType, blocks: [RunBlock] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.blocks = blocks
    }

    /// Adds a block where it belongs: a warm-up first, a cool-down last, anything else just
    /// before a cool-down at the end (so it doesn't land after it).
    public mutating func insert(_ block: RunBlock) {
        switch block.steps.first?.kind {
        case .warmUp?:
            blocks.insert(block, at: 0)
        case .coolDown?:
            blocks.append(block)
        default:
            if let last = blocks.last, last.repeats == 1, last.steps.allSatisfy({ $0.kind == .coolDown }) {
                blocks.insert(block, at: blocks.count - 1)
            } else {
                blocks.append(block)
            }
        }
    }

    /// Swaps a block with the one above (`by: -1`) or below (`by: 1`).
    public mutating func moveBlock(at index: Int, by offset: Int) {
        let target = index + offset
        guard blocks.indices.contains(index), blocks.indices.contains(target) else { return }
        blocks.swapAt(index, target)
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
                    } else if type == .race && step.kind == .work {
                        label = "Race"
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
        let blocks: [RunBlock]
        switch type {
        case .free:
            blocks = []
        case .easy:
            blocks = [RunBlock(steps: [step(.steady, km: 6, pace(.easy))])]
        case .recovery:
            blocks = [RunBlock(steps: [step(.steady, minutes: 30, nil)])]
        case .long:
            blocks = [RunBlock(steps: [step(.steady, km: 15, pace(.easy))])]
        case .tempo:
            blocks = [
                RunBlock(steps: [step(.warmUp, km: 2)]),
                RunBlock(repeats: 2, steps: [step(.work, minutes: 10, pace(.threshold)), step(.recovery, minutes: 2)]),
                RunBlock(steps: [step(.coolDown, km: 2)])
            ]
        case .intervals:
            blocks = [
                RunBlock(steps: [step(.warmUp, km: 2)]),
                RunBlock(repeats: 6, steps: [step(.work, km: 0.8, pace(.interval)), step(.recovery, minutes: 1.5)]),
                RunBlock(steps: [step(.coolDown, km: 2)])
            ]
        case .progression:
            blocks = [RunBlock(steps: [
                step(.steady, km: 3, pace(.easy)),
                step(.steady, km: 3, pace(.marathon)),
                step(.work, km: 2, pace(.threshold))
            ])]
        case .race:
            return Self.race(meters: 5000, zones: zones)
        case .fartlek:
            blocks = [
                RunBlock(steps: [step(.warmUp, minutes: 10)]),
                RunBlock(repeats: 8, steps: [step(.work, minutes: 1, pace(.interval)), step(.recovery, minutes: 1)]),
                RunBlock(steps: [step(.coolDown, minutes: 10)])
            ]
        }
        return CustomRunWorkout(name: type.displayName, type: type, blocks: blocks)
    }
}

extension CustomRunWorkout {
    /// Race distances offered on the Record tab.
    public static let raceDistances: [(name: String, meters: Double)] = [
        ("5K", 5000), ("10K", 10000), ("Half marathon", 21097.5), ("Marathon", 42195),
    ]

    /// A race: one step of the full distance, with their race pace for it as the target.
    public static func race(meters: Double, zones: PaceZones?) -> CustomRunWorkout {
        let zone: PaceZone = meters <= 6000 ? .fiveK : meters <= 15000 ? .tenK : meters <= 30000 ? .halfMarathon : .marathon
        let target = zones.map { PaceTarget.single(Pace(secondsPerKm: ($0.typicalPace(for: zone).secondsPerKm / 5).rounded() * 5)) }
        let name = raceDistances.first { $0.meters == meters }?.name
            ?? String(format: "%g km", (meters / 100).rounded() / 10)
        return CustomRunWorkout(name: "\(name) race", type: .race,
                                blocks: [RunBlock(steps: [WorkoutStep(kind: .work, length: .distance(meters: meters), target: target)])])
    }

    /// The race distance, for a race.
    public var raceMeters: Double? {
        guard type == .race, case .distance(let meters)? = blocks.flatMap(\.steps).first(where: { $0.kind == .work })?.length else { return nil }
        return meters
    }
}

extension CustomRunWorkout {
    /// A saved workout from a run's steps (e.g. a finished planned session), with repeats
    /// folded back into blocks: warm-up, 6 × (800 m + 90 s jog), cool-down.
    public init(name: String, type: RecordRunType, structure: RunStructure) {
        let steps = structure.segments.map { segment in
            WorkoutStep(kind: segment.kind, length: segment.length, target: segment.targetPace.map(PaceTarget.range))
        }
        func same(_ a: WorkoutStep, _ b: WorkoutStep) -> Bool {
            a.kind == b.kind && a.length == b.length && a.target == b.target
        }
        var blocks: [RunBlock] = []
        var loose: [WorkoutStep] = []
        func flushLoose() {
            if !loose.isEmpty { blocks.append(RunBlock(repeats: 1, steps: loose)) }
            loose = []
        }
        var i = 0
        while i < steps.count {
            // A repeating pattern of one or two steps (rep, or rep + recovery) starting with work.
            var found: (length: Int, repeats: Int)?
            if steps[i].kind == .work {
                for length in [2, 1] where i + length <= steps.count {
                    let pattern = Array(steps[i..<(i + length)])
                    if length == 2 && pattern[1].kind == .work { continue }
                    var repeats = 1
                    var next = i + length
                    while next + length <= steps.count, zip(pattern, steps[next..<(next + length)]).allSatisfy(same) {
                        repeats += 1
                        next += length
                    }
                    // The last rep often has no recovery after it.
                    var lastRepAlone = false
                    if length == 2, next < steps.count, same(steps[next], pattern[0]) {
                        repeats += 1
                        lastRepAlone = true
                    }
                    if repeats >= 2 {
                        found = (length, repeats)
                        i = next + (lastRepAlone ? 1 : 0)
                        flushLoose()
                        blocks.append(RunBlock(repeats: repeats, steps: pattern.map { WorkoutStep(kind: $0.kind, length: $0.length, target: $0.target) }))
                        break
                    }
                }
            }
            if found == nil {
                loose.append(steps[i])
                i += 1
            }
        }
        flushLoose()
        self.init(name: name, type: type, blocks: blocks)
    }
}

extension RecordRunType {
    /// The saved-workout type for a plan session type.
    public init(session: RunSessionType?) {
        switch session {
        case .easy: self = .easy
        case .recovery: self = .recovery
        case .long: self = .long
        case .tempo: self = .tempo
        case .intervals: self = .intervals
        case nil: self = .free
        }
    }
}
