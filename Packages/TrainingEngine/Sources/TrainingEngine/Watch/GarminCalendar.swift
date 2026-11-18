import Foundation

/// Planned runs as Garmin Training API workouts, for the Garmin Connect calendar (they then
/// sync to any Garmin watch and run in Garmin's own workout screens). The app sends these to
/// Kinetix's `garmin` Supabase function, which holds the Garmin keys and publishes them.
///
/// Field names follow Garmin's Training API workout format. Check them against Garmin's
/// documentation when the developer programme approves Kinetix (docs/GARMIN_TRAINING_API.md);
/// this file is the only place in the app that knows the format.
public enum GarminCalendar {
    public struct Workout: Encodable, Equatable, Sendable {
        public var workoutName: String
        public var description: String?
        public var sport = "RUNNING"
        public var workoutProvider = "Kinetix"
        public var workoutSourceId = "Kinetix"
        public var steps: [Step]
    }

    public enum Step: Encodable, Equatable, Sendable {
        case step(WorkoutStep)
        case repeats(RepeatStep)

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .step(let step): try step.encode(to: encoder)
            case .repeats(let block): try block.encode(to: encoder)
            }
        }
    }

    public struct WorkoutStep: Encodable, Equatable, Sendable {
        public var type = "WorkoutStep"
        public var stepOrder: Int
        /// WARMUP, ACTIVE, INTERVAL, RECOVERY, COOLDOWN.
        public var intensity: String
        public var description: String?
        /// DISTANCE (metres) or TIME (seconds).
        public var durationType: String
        public var durationValue: Double
        /// PACE (with speeds in metres per second) or OPEN.
        public var targetType: String
        /// Slowest speed allowed (m/s).
        public var targetValueLow: Double?
        /// Fastest speed allowed (m/s).
        public var targetValueHigh: Double?
    }

    public struct RepeatStep: Encodable, Equatable, Sendable {
        public var type = "WorkoutRepeatStep"
        public var stepOrder: Int
        public var repeatType = "REPEAT_UNTIL_STEPS_CMPLT"
        public var repeatValue: Int
        public var steps: [WorkoutStep]
    }

    /// One planned session for the calendar, as the app sends it to the server.
    public struct Scheduled: Encodable, Equatable, Sendable {
        /// The planned session's id: the server replaces or removes the Garmin copy by it.
        public var sessionId: String
        /// yyyy-MM-dd in the runner's calendar.
        public var date: String
        public var workout: Workout
    }

    /// A planned run: warm-up, repeats (rep + recovery pairs become one repeat block, as for
    /// the Apple Workout app) and cool-down. Steps run by effort (`paceIsGuide`) have no pace
    /// target, so the watch doesn't nag.
    public static func workout(title: String, description: String? = nil, structure: RunStructure) -> Workout {
        let blocks = WorkoutBlocks(structure: structure)
        var order = 0
        func next() -> Int { order += 1; return order }
        func step(_ segment: RunSegment, inRepeat: Bool) -> WorkoutStep {
            let target = segment.paceIsGuide == true ? nil : segment.targetPace
            let duration: (String, Double)
            switch segment.length {
            case .distance(let meters): duration = ("DISTANCE", meters.rounded())
            case .duration(let seconds): duration = ("TIME", seconds.rounded())
            }
            return WorkoutStep(stepOrder: next(), intensity: intensity(segment.kind, inRepeat: inRepeat), description: segment.label,
                               durationType: duration.0, durationValue: duration.1,
                               targetType: target == nil ? "OPEN" : "PACE",
                               targetValueLow: target.map { speed($0.slowest) },
                               targetValueHigh: target.map { speed($0.fastest) })
        }
        var steps: [Step] = []
        if let warmUp = blocks.warmUp { steps.append(.step(step(warmUp, inRepeat: false))) }
        for block in blocks.blocks {
            if block.iterations > 1 {
                let repeatOrder = next()
                steps.append(.repeats(RepeatStep(stepOrder: repeatOrder, repeatValue: block.iterations,
                                                  steps: block.steps.map { step($0, inRepeat: true) })))
            } else {
                steps += block.steps.map { .step(step($0, inRepeat: false)) }
            }
        }
        if let coolDown = blocks.coolDown { steps.append(.step(step(coolDown, inRepeat: false))) }
        return Workout(workoutName: String(title.prefix(40)), description: description, steps: steps)
    }

    static func intensity(_ kind: SegmentKind, inRepeat: Bool) -> String {
        switch kind {
        case .warmUp: return "WARMUP"
        case .coolDown: return "COOLDOWN"
        case .recovery: return "RECOVERY"
        case .work: return inRepeat ? "INTERVAL" : "ACTIVE"
        case .steady: return "ACTIVE"
        }
    }

    /// Metres per second, to three decimals.
    static func speed(_ pace: Pace) -> Double {
        guard pace.secondsPerKm > 0 else { return 0 }
        return (1000 / pace.secondsPerKm * 1000).rounded() / 1000
    }

    /// yyyy-MM-dd for a day in this calendar.
    public static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
