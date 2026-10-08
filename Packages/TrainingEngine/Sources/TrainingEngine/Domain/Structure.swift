import Foundation

/// How long a run segment lasts.
public enum SegmentLength: Codable, Equatable, Hashable, Sendable {
    case duration(seconds: Double)
    case distance(meters: Double)
}

public enum SegmentKind: String, Codable, CaseIterable, Sendable {
    case warmUp, work, recovery, coolDown, steady

    /// Pace cues are off in these segments unless the user opts in.
    public var isEasyBookend: Bool { self == .warmUp || self == .coolDown }
}

public struct RunSegment: Codable, Equatable, Hashable, Sendable {
    public var kind: SegmentKind
    public var length: SegmentLength
    public var targetPace: PaceRange?
    public var label: String?

    public init(kind: SegmentKind, length: SegmentLength, targetPace: PaceRange? = nil, label: String? = nil) {
        self.kind = kind
        self.length = length
        self.targetPace = targetPace
        self.label = label
    }
}

/// The ordered segments of a structured run.
public struct RunStructure: Codable, Equatable, Sendable {
    public var segments: [RunSegment]

    public init(segments: [RunSegment]) {
        self.segments = segments
    }
}

public struct RepRange: Codable, Equatable, Hashable, Sendable {
    public var lower: Int
    public var upper: Int

    public init(_ lower: Int, _ upper: Int) {
        self.lower = min(lower, upper)
        self.upper = max(lower, upper)
    }
}

public struct ExercisePrescription: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: Int
    public var repRange: RepRange
    /// Nil for bodyweight movements.
    public var weightKg: Double?
    public var restSeconds: Int

    public init(exerciseId: String, sets: Int, repRange: RepRange, weightKg: Double?, restSeconds: Int) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.repRange = repRange
        self.weightKg = weightKg
        self.restSeconds = restSeconds
    }
}

public struct StrengthPrescription: Codable, Equatable, Sendable {
    public var exercises: [ExercisePrescription]

    public init(exercises: [ExercisePrescription]) {
        self.exercises = exercises
    }
}
