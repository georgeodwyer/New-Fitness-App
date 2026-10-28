import Foundation

/// A run's parts grouped the way watch workout apps want them: a warm-up, repeated blocks
/// ("8 × 400 m + 200 m jog"), and a cool-down. Used to send planned runs to Apple's
/// Workout app.
public struct WorkoutBlocks: Equatable, Sendable {
    public struct Block: Equatable, Sendable {
        public var steps: [RunSegment]
        public var iterations: Int
    }

    public var warmUp: RunSegment?
    public var blocks: [Block]
    public var coolDown: RunSegment?

    public init(structure: RunStructure) {
        var segments = structure.segments
        warmUp = segments.first?.kind == .warmUp ? segments.removeFirst() : nil
        coolDown = segments.last?.kind == .coolDown ? segments.removeLast() : nil
        blocks = Self.group(segments)
    }

    /// Repeats of the same rep + recovery pair become one block with that many iterations;
    /// everything else (a last rep with no jog after it, steady runs) is a block of one.
    static func group(_ segments: [RunSegment]) -> [Block] {
        var blocks: [Block] = []
        var index = 0
        while index < segments.count {
            let segment = segments[index]
            if segment.kind == .work, index + 1 < segments.count, segments[index + 1].kind == .recovery {
                let pair = [segment, segments[index + 1]]
                var count = 1
                var next = index + 2
                while next + 1 < segments.count, Self.same(segments[next], pair[0]), Self.same(segments[next + 1], pair[1]) {
                    count += 1
                    next += 2
                }
                blocks.append(Block(steps: pair, iterations: count))
                index = next
                continue
            }
            blocks.append(Block(steps: [segment], iterations: 1))
            index += 1
        }
        return blocks
    }

    private static func same(_ a: RunSegment, _ b: RunSegment) -> Bool {
        a.kind == b.kind && a.length == b.length && a.targetPace == b.targetPace
    }
}
