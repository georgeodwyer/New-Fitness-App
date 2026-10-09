import Foundation

/// Generates realistic GPS samples for a structured run — used by tests and by the app's
/// "simulated GPS" mode (no need to go outside to try the run trainer).
///
/// The runner follows each segment's target pace, with optional scripted deviations
/// (to demonstrate pace cues), slowly wandering GPS drift, and noisy Doppler speed.
public struct SimulatedRunner: Sendable {
    /// A pace override for part of a segment.
    public struct Deviation: Sendable, Equatable {
        public var segmentIndex: Int
        /// Seconds into the segment.
        public var from: Double
        public var to: Double
        /// Multiplier applied to speed (1.1 = 10% faster).
        public var speedFactor: Double

        public init(segmentIndex: Int, from: Double, to: Double, speedFactor: Double) {
            self.segmentIndex = segmentIndex
            self.from = from
            self.to = to
            self.speedFactor = speedFactor
        }
    }

    public var segments: [RunSegment]
    public var deviations: [Deviation]
    /// Pace used when a segment has no target (and after the structure ends).
    public var defaultPace: Pace
    /// Loop centre (default: Hyde Park, London) and radius.
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var loopRadiusMeters: Double
    /// GPS noise: drift amplitude (m) and speed noise (m/s standard deviation).
    public var driftMeters: Double
    public var speedNoise: Double
    public var seed: UInt64

    public init(
        structure: RunStructure?,
        deviations: [Deviation] = [],
        defaultPace: Pace = Pace(secondsPerKm: 330),
        centerLatitude: Double = 51.5073,
        centerLongitude: Double = -0.1657,
        loopRadiusMeters: Double = 400,
        driftMeters: Double = 3,
        speedNoise: Double = 0.25,
        seed: UInt64 = 42
    ) {
        self.segments = structure?.segments ?? []
        self.deviations = deviations
        self.defaultPace = defaultPace
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.loopRadiusMeters = loopRadiusMeters
        self.driftMeters = driftMeters
        self.speedNoise = speedNoise
        self.seed = seed
    }

    /// A demo profile: the first work rep (or main segment) starts 12% too fast for 45 s,
    /// and a later one drifts 10% too slow — so pace cues fire.
    public static func demo(structure: RunStructure?) -> SimulatedRunner {
        let segments = structure?.segments ?? []
        let targeted = segments.indices.filter { segments[$0].kind == .work || segments[$0].kind == .steady }
        var deviations: [Deviation] = []
        if let first = targeted.first {
            deviations.append(Deviation(segmentIndex: first, from: 5, to: 50, speedFactor: 1.12))
        }
        if targeted.count > 1, let later = targeted.dropFirst().first {
            deviations.append(Deviation(segmentIndex: later, from: 10, to: 60, speedFactor: 0.9))
        } else if let only = targeted.first {
            deviations.append(Deviation(segmentIndex: only, from: 120, to: 170, speedFactor: 0.9))
        }
        return SimulatedRunner(structure: structure, deviations: deviations)
    }

    /// Samples every `interval` seconds from `start` for `duration` seconds.
    public func samples(start: Date, duration: Double, interval: Double = 1) -> [LocationSample] {
        var generator = Generator(runner: self)
        var result: [LocationSample] = []
        var t = 0.0
        while t <= duration {
            result.append(generator.sample(at: t, start: start))
            t += interval
        }
        return result
    }

    /// Stateful sample generator (for live playback).
    public struct Generator: Sendable {
        let runner: SimulatedRunner
        private var rng: SeededRandom
        private var lastTime = 0.0
        private var distance = 0.0
        private var segmentIndex = 0
        private var segmentStartTime = 0.0
        private var segmentStartDistance = 0.0
        private var driftNorth = 0.0
        private var driftEast = 0.0

        public init(runner: SimulatedRunner) {
            self.runner = runner
            self.rng = SeededRandom(seed: runner.seed)
        }

        /// The sample at `t` seconds after start. Call with increasing `t`.
        public mutating func sample(at t: Double, start: Date) -> LocationSample {
            let dt = max(0, t - lastTime)
            lastTime = t
            let speed = trueSpeed(at: t)
            distance += speed * dt
            advanceSegments(time: t)

            // Slowly wandering drift (mean-reverting), like real filtered GPS.
            driftNorth = driftNorth * 0.98 + rng.normal() * runner.driftMeters * 0.15
            driftEast = driftEast * 0.98 + rng.normal() * runner.driftMeters * 0.15

            let angle = distance / runner.loopRadiusMeters
            let north = runner.loopRadiusMeters * sin(angle) + driftNorth
            let east = runner.loopRadiusMeters * (1 - cos(angle)) + driftEast
            let (lat, lon) = Geo.offset(latitude: runner.centerLatitude, longitude: runner.centerLongitude,
                                        northMeters: north, eastMeters: east)
            let reportedSpeed = max(0, speed + rng.normal() * runner.speedNoise)
            return LocationSample(timestamp: start.addingTimeInterval(t), latitude: lat, longitude: lon,
                                  horizontalAccuracy: 5, speed: reportedSpeed)
        }

        private mutating func advanceSegments(time: Double) {
            while segmentIndex < runner.segments.count {
                let segment = runner.segments[segmentIndex]
                let done: Bool
                switch segment.length {
                case .duration(let seconds): done = time - segmentStartTime >= seconds
                case .distance(let meters): done = distance - segmentStartDistance >= meters
                }
                guard done else { break }
                segmentIndex += 1
                segmentStartTime = time
                segmentStartDistance = distance
            }
        }

        private func trueSpeed(at t: Double) -> Double {
            var pace = runner.defaultPace
            var factor = 1.0
            if segmentIndex < runner.segments.count {
                let segment = runner.segments[segmentIndex]
                if let target = segment.targetPace {
                    pace = Pace(secondsPerKm: (target.fastest.secondsPerKm + target.slowest.secondsPerKm) / 2)
                }
                let into = t - segmentStartTime
                for deviation in runner.deviations where deviation.segmentIndex == segmentIndex && into >= deviation.from && into < deviation.to {
                    factor = deviation.speedFactor
                }
            }
            return 1000 / pace.secondsPerKm * factor
        }
    }
}

/// Small deterministic random generator (so simulated runs are repeatable).
public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    public mutating func next() -> Double {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 2_685_821_657_736_338_717
        return Double(value >> 11) / Double(1 << 53)
    }

    /// Standard normal (Box–Muller).
    public mutating func normal() -> Double {
        let u1 = max(next(), 1e-12), u2 = next()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
