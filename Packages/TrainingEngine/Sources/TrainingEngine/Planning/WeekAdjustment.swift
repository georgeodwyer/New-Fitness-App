import Foundation

/// How last week felt, from the weekly check-in.
public enum WeekFeel: String, Codable, CaseIterable, Sendable {
    case tooMuch, aboutRight, tooEasy

    public var title: String {
        switch self {
        case .tooMuch: return "Too much"
        case .aboutRight: return "About right"
        case .tooEasy: return "Too easy"
        }
    }
}

/// Next week made a little lighter or harder after the weekly check-in.
public enum WeekAdjustment {
    /// A run made `factor` as big. Reps sessions lose (or keep) a rep rather than every rep
    /// getting shorter; steady runs scale their length (warm-up and cool-down stay as they are).
    public static func scaled(_ structure: RunStructure, by factor: Double) -> RunStructure {
        var segments = structure.segments
        let workIndexes = segments.indices.filter { segments[$0].kind == .work }
        if workIndexes.count >= 3 {
            guard factor < 1, let last = workIndexes.last else { return structure }
            // One rep fewer: the last rep and the recovery before it.
            var remove = [last]
            if last > 0, segments[last - 1].kind == .recovery { remove.append(last - 1) }
            for index in remove.sorted(by: >) { segments.remove(at: index) }
            return RunStructure(segments: segments)
        }
        for index in segments.indices where segments[index].kind != .warmUp && segments[index].kind != .coolDown {
            switch segments[index].length {
            case .distance(let meters):
                segments[index].length = .distance(meters: max(100, (meters * factor / 100).rounded() * 100))
            case .duration(let seconds):
                segments[index].length = .duration(seconds: max(60, (seconds * factor / 30).rounded() * 30))
            }
        }
        return RunStructure(segments: segments)
    }

    /// A lighter gym session: one set fewer on the accessories (never below two).
    public static func lighter(_ prescription: StrengthPrescription) -> StrengthPrescription {
        var copy = prescription
        for index in copy.exercises.indices where copy.exercises[index].role == .accessory {
            copy.exercises[index].sets = max(2, copy.exercises[index].sets - 1)
        }
        return copy
    }
}
