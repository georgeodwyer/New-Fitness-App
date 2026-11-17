import Foundation

/// The step counter's running total at a moment of active running.
public struct StepSample: Codable, Equatable, Sendable {
    /// Seconds of active running (pauses excluded), like `HeartRateSample.elapsed`.
    public var elapsed: Double
    /// Steps so far.
    public var steps: Double

    public init(elapsed: Double, steps: Double) {
        self.elapsed = elapsed
        self.steps = steps
    }
}

/// Cadence (steps per minute) and stride length (metres per step) from a run's step samples.
/// Shown only when there are enough steps to mean something (not a simulated or walking-pace
/// glitch): at least two minutes and 200 steps.
public enum RunCadence {
    static let minimumSeconds: Double = 120
    static let minimumSteps: Double = 200

    /// Steps by this point of the run, interpolated between samples.
    public static func steps(at elapsed: Double, in samples: [StepSample]) -> Double {
        guard let first = samples.first else { return 0 }
        if elapsed <= first.elapsed { return first.elapsed > 0 ? first.steps * max(elapsed, 0) / first.elapsed : first.steps }
        for (a, b) in zip(samples, samples.dropFirst()) where elapsed <= b.elapsed {
            let span = b.elapsed - a.elapsed
            return span > 0 ? a.steps + (b.steps - a.steps) * (elapsed - a.elapsed) / span : b.steps
        }
        return samples.last?.steps ?? 0
    }

    /// Whole-run average, steps per minute.
    public static func averageCadence(_ samples: [StepSample]?, durationSeconds: Double) -> Double? {
        guard let total = samples?.last?.steps, total >= minimumSteps, durationSeconds >= minimumSeconds else { return nil }
        return total / durationSeconds * 60
    }

    /// Whole-run average stride length, metres.
    public static func averageStride(_ samples: [StepSample]?, distanceMeters: Double, durationSeconds: Double) -> Double? {
        guard averageCadence(samples, durationSeconds: durationSeconds) != nil, let total = samples?.last?.steps,
              distanceMeters >= 200 else { return nil }
        return distanceMeters / total
    }

    public struct SplitSteps: Equatable, Sendable {
        /// Steps per minute.
        public var cadence: Double
        /// Metres per step.
        public var strideMeters: Double
    }

    /// Cadence and stride for each split (nil for a split with too few steps to judge).
    public static func perSplit(_ splits: [Split], samples: [StepSample]?, splitMeters: Double) -> [SplitSteps?] {
        guard let samples, !samples.isEmpty else { return splits.map { _ in nil } }
        var start = 0.0
        return splits.map { split in
            let end = start + split.durationSeconds
            defer { start = end }
            let steps = Self.steps(at: end, in: samples) - Self.steps(at: start, in: samples)
            guard split.durationSeconds > 0, steps >= 50 else { return nil }
            return SplitSteps(cadence: steps / split.durationSeconds * 60, strideMeters: splitMeters / steps)
        }
    }

    /// Cadence through the run, in 30-second windows, for a chart.
    public static func series(_ samples: [StepSample]?, windowSeconds: Double = 30) -> [RunChartPoint] {
        guard let samples, let last = samples.last, last.elapsed >= minimumSeconds else { return [] }
        var points: [RunChartPoint] = []
        var start = 0.0
        while start < last.elapsed {
            let end = min(start + windowSeconds, last.elapsed)
            let span = end - start
            if span >= windowSeconds / 2 {
                let steps = Self.steps(at: end, in: samples) - Self.steps(at: start, in: samples)
                let cadence = steps / span * 60
                // Standing still (a pause in the step count) isn't plotted.
                if cadence >= 60 { points.append(RunChartPoint(elapsed: (start + end) / 2, value: cadence)) }
            }
            start = end
        }
        return points
    }
}
