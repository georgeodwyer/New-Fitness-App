import Foundation

public enum Discipline: String, Codable, CaseIterable, Sendable {
    case run, strength, crossTraining, mobility
}

public enum RunSessionType: String, Codable, CaseIterable, Sendable {
    case easy, recovery, long, tempo, intervals

    /// "Quality" runs are the hard ones the scheduler protects from heavy leg days.
    public var isQuality: Bool {
        switch self {
        case .tempo, .intervals, .long: return true
        case .easy, .recovery: return false
        }
    }
}

public enum StrengthFocus: String, Codable, CaseIterable, Sendable {
    case fullBody, upper, lower, push, pull, legs

    /// True when the session loads the legs heavily (interference with running).
    public var loadsLowerBody: Bool {
        switch self {
        case .fullBody, .lower, .legs: return true
        case .upper, .push, .pull: return false
        }
    }
}

public enum SessionSlot: String, Codable, CaseIterable, Sendable {
    case morning, evening
}

public enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case planned, completed, skipped, swapped
}

/// What kind of session this is, across all disciplines.
public enum SessionKind: Codable, Equatable, Hashable, Sendable {
    case run(RunSessionType)
    case strength(StrengthFocus)
    case crossTraining
    case mobility

    public var discipline: Discipline {
        switch self {
        case .run: return .run
        case .strength: return .strength
        case .crossTraining: return .crossTraining
        case .mobility: return .mobility
        }
    }

    public var displayName: String {
        switch self {
        case .run(let type):
            switch type {
            case .easy: return "Easy Run"
            case .recovery: return "Recovery Run"
            case .long: return "Long Run"
            case .tempo: return "Tempo Run"
            case .intervals: return "Intervals"
            }
        case .strength(let focus):
            switch focus {
            case .fullBody: return "Full Body Strength"
            case .upper: return "Upper Body Strength"
            case .lower: return "Lower Body Strength"
            case .push: return "Push Strength"
            case .pull: return "Pull Strength"
            case .legs: return "Leg Strength"
            }
        case .crossTraining: return "Low-Impact Cardio"
        case .mobility: return "Mobility"
        }
    }
}
