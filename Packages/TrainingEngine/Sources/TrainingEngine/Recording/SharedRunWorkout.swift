import Foundation

/// A custom run shared with a friend: the structure, with each pace stored as an effort
/// (a share of the sender's fitness) rather than a fixed pace, so it becomes the friend's own
/// pace when they open it. e.g. the sender's 4:30/km threshold reps become the friend's
/// threshold pace. The sender's paces travel too, for a friend without a profile.
public struct SharedRunWorkout: Codable, Equatable, Sendable {
    /// Bumped if the format changes in a way older apps can't read.
    public static let currentFormat = 1

    public struct Effort: Codable, Equatable, Sendable {
        /// The pace's oxygen cost as a share of the sender's VDOT (0.86–0.89 is threshold).
        public var fastest: Double
        public var slowest: Double
        /// The sender's paces, seconds per km.
        public var fastestSecondsPerKm: Double
        public var slowestSecondsPerKm: Double
    }

    public struct Step: Codable, Equatable, Sendable {
        public var kind: SegmentKind
        public var length: SegmentLength
        public var effort: Effort?
    }

    public struct Block: Codable, Equatable, Sendable {
        public var repeats: Int
        public var steps: [Step]
    }

    public var format: Int
    public var name: String
    public var type: RecordRunType
    public var blocks: [Block]

    /// The sender's workout, with paces turned into efforts using the sender's zones.
    public init(_ workout: CustomRunWorkout, zones: PaceZones) {
        format = Self.currentFormat
        name = workout.name
        type = workout.type
        blocks = workout.blocks.map { block in
            Block(repeats: block.repeats, steps: block.steps.map { step in
                Step(kind: step.kind, length: step.length, effort: step.target.map { target in
                    let range = target.range
                    return Effort(fastest: PaceZones.intensity(of: range.fastest, vdot: zones.vdot),
                                  slowest: PaceZones.intensity(of: range.slowest, vdot: zones.vdot),
                                  fastestSecondsPerKm: range.fastest.secondsPerKm, slowestSecondsPerKm: range.slowest.secondsPerKm)
                })
            })
        }
    }

    /// The workout with the recipient's own paces (or the sender's, without zones), rounded to
    /// whole seconds. A single pace stays a single pace.
    public func workout(for zones: PaceZones?) -> CustomRunWorkout {
        func pace(_ intensity: Double, original: Double) -> Pace {
            guard let zones else { return Pace(secondsPerKm: original.rounded()) }
            return Pace(secondsPerKm: PaceZones.pace(forVO2: intensity * zones.vdot).secondsPerKm.rounded())
        }
        return CustomRunWorkout(name: name, type: type, blocks: blocks.map { block in
            RunBlock(repeats: block.repeats, steps: block.steps.map { step in
                WorkoutStep(kind: step.kind, length: step.length, target: step.effort.map { effort in
                    let fastest = pace(effort.fastest, original: effort.fastestSecondsPerKm)
                    let slowest = pace(effort.slowest, original: effort.slowestSecondsPerKm)
                    return fastest == slowest ? .single(fastest) : .range(PaceRange(fastest: fastest, slowest: slowest))
                })
            })
        })
    }

    /// "Threshold", "Easy"… for an effort: the named zone it's closest to.
    public static func effortName(_ effort: Effort) -> String {
        let middle = (effort.fastest + effort.slowest) / 2
        let named: [(String, PaceZone)] = [("Easy", .easy), ("Marathon", .marathon), ("Threshold", .threshold),
                                           ("Interval", .interval), ("Repetition", .repetition)]
        let best = named.min { a, b in
            abs(PaceZones.bandMiddle(a.1) - middle) < abs(PaceZones.bandMiddle(b.1) - middle)
        }
        return best?.0 ?? "Easy"
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// nil when the data isn't a shared workout this version can read.
    public static func decode(_ data: Data) -> SharedRunWorkout? {
        guard let shared = try? JSONDecoder().decode(SharedRunWorkout.self, from: data),
              shared.format <= currentFormat else { return nil }
        return shared
    }
}

extension PaceZones {
    /// The oxygen cost of running at a pace, as a share of a VDOT.
    static func intensity(of pace: Pace, vdot: Double) -> Double {
        guard pace.secondsPerKm > 0, vdot > 0 else { return 0 }
        let velocity = 60_000 / pace.secondsPerKm // metres per minute
        return (-4.60 + 0.182258 * velocity + 0.000104 * velocity * velocity) / vdot
    }

    static func bandMiddle(_ zone: PaceZone) -> Double {
        guard let band = intensityBands[zone] else { return 0 }
        return (band.slow + band.fast) / 2
    }
}
