import Foundation

/// Rolling-average pace from GPS so momentary jitter doesn't swing the reading.
/// Uses the chip's Doppler speed when available (more precise than positions);
/// otherwise distance travelled over the window.
public struct PaceSmoother: Sendable {
    public var windowSeconds: Double
    private var entries: [(time: Double, distance: Double, speed: Double)] = []

    public init(windowSeconds: Double = 20) {
        self.windowSeconds = windowSeconds
    }

    /// `time` is active seconds; `distance` cumulative metres; `speed` m/s or negative if unknown.
    public mutating func add(time: Double, distance: Double, speed: Double) {
        entries.append((time, distance, speed))
        let cutoff = time - windowSeconds
        // Keep one entry at/just before the cutoff so the window spans fully.
        while entries.count > 2, entries[1].time <= cutoff { entries.removeFirst() }
    }

    public mutating func reset() { entries.removeAll() }

    /// Smoothed pace at the latest sample, or nil when there's too little data or
    /// the runner is (nearly) stationary.
    public var pace: Pace? {
        guard let last = entries.last, let first = entries.first else { return nil }
        let span = last.time - first.time
        guard span >= min(8, windowSeconds / 2) else { return nil }
        let speeds = entries.dropFirst().map(\.speed)
        let meanSpeed: Double
        if !speeds.isEmpty, speeds.allSatisfy({ $0 >= 0 }) {
            meanSpeed = speeds.reduce(0, +) / Double(speeds.count)
        } else {
            meanSpeed = (last.distance - first.distance) / span
        }
        // Below ~1 m/s (16:40/km) treat as stopped.
        return meanSpeed >= 1.0 ? Pace(metersPerSecond: meanSpeed) : nil
    }
}
