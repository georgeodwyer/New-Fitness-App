import Foundation

/// One km (or mile) split.
public struct Split: Codable, Equatable, Sendable {
    /// 1-based.
    public var index: Int
    public var durationSeconds: Double
    /// Pace of this split.
    public var pace: Pace
    /// Average pace of the whole run so far.
    public var averagePace: Pace
    public var averageHeartRate: Double?
}

/// A lap the runner marked by hand (watch double tap, crown or the Lap button).
public struct Lap: Codable, Equatable, Sendable {
    /// 1-based.
    public var index: Int
    public var durationSeconds: Double
    public var distanceMeters: Double
    public var averageHeartRate: Double?
    /// Run time when the lap ended.
    public var endElapsedSeconds: Double

    public init(index: Int, durationSeconds: Double, distanceMeters: Double, averageHeartRate: Double? = nil, endElapsedSeconds: Double) {
        self.index = index
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.endElapsedSeconds = endElapsedSeconds
    }

    public var pace: Pace? {
        distanceMeters > 20 && durationSeconds > 0 ? Pace(metersPerSecond: distanceMeters / durationSeconds) : nil
    }
}

/// How a segment actually went.
public struct SegmentResult: Codable, Equatable, Sendable {
    public var index: Int
    public var segment: RunSegment
    public var durationSeconds: Double
    public var distanceMeters: Double
    public var averagePace: Pace?
    /// Seconds within target (when the segment has one and pace was available).
    public var secondsInTarget: Double
    public var secondsMeasured: Double
}

public struct PaceCue: Codable, Equatable, Sendable {
    public var direction: PaceRange.Position
    public var pace: Pace
    public var target: PaceRange
    public var message: String
}

/// Something worth telling the runner. Each has a spoken `announcement`.
public enum RunEvent: Equatable, Sendable {
    case segmentStarted(index: Int, segment: RunSegment, announcement: String)
    /// A step's time or distance is up and steps don't move on by themselves: waiting for Next step.
    case stepEnded(index: Int, next: RunSegment, announcement: String)
    case paceCue(PaceCue)
    case split(Split, announcement: String)
    case workoutComplete(announcement: String)

    public var announcement: String {
        switch self {
        case .segmentStarted(_, _, let text): return text
        case .stepEnded(_, _, let text): return text
        case .paceCue(let cue): return cue.message
        case .split(_, let text): return text
        case .workoutComplete(let text): return text
        }
    }
}

/// What the run screen shows right now.
public struct RunSnapshot: Codable, Equatable, Sendable {
    public var elapsedSeconds: Double
    public var distanceMeters: Double
    public var currentPace: Pace?
    public var averagePace: Pace?
    public var segmentIndex: Int?
    public var segment: RunSegment?
    public var nextSegment: RunSegment?
    /// 0...1 progress through the current segment.
    public var segmentProgress: Double
    /// Seconds or metres left in the segment, as a display-ready value.
    public var segmentRemaining: SegmentLength?
    public var paceStatus: PaceRange.Position?
    public var timeInTargetSeconds: Double
    public var targetedSeconds: Double
    public var heartRate: Double?
    public var isPaused: Bool
    public var isStructureComplete: Bool
    public var lastCue: PaceCue?
    public var gpsAvailable: Bool
    /// The lap in progress (2 after the first marked lap); nil until a lap is marked.
    public var lapNumber: Int? = nil
    public var lapElapsedSeconds: Double? = nil
    public var lapDistanceMeters: Double? = nil
    /// The last lap marked.
    public var lastLap: Lap? = nil
    /// The step is done and waiting for Next step (steps not moving on by themselves).
    public var isWaitingForNextStep: Bool? = nil
}

public struct RunSummary: Codable, Equatable, Sendable {
    public var durationSeconds: Double
    public var distanceMeters: Double
    public var averagePace: Pace?
    public var splits: [Split]
    public var segments: [SegmentResult]
    public var timeInTargetSeconds: Double
    public var targetedSeconds: Double
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var route: [RoutePoint]
    /// Heart rate through the run (at most one sample every 5 s).
    public var heartRateSamples: [HeartRateSample] = []
    /// Laps marked by hand (nil when none were).
    public var laps: [Lap]? = nil

    /// For building a summary outside the engine (e.g. a run sent from the watch, tests).
    public init(durationSeconds: Double, distanceMeters: Double, averagePace: Pace?, splits: [Split] = [], segments: [SegmentResult] = [],
                timeInTargetSeconds: Double = 0, targetedSeconds: Double = 0, averageHeartRate: Double? = nil, maxHeartRate: Double? = nil,
                route: [RoutePoint] = [], heartRateSamples: [HeartRateSample] = [], laps: [Lap]? = nil) {
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averagePace = averagePace
        self.splits = splits
        self.segments = segments
        self.timeInTargetSeconds = timeInTargetSeconds
        self.targetedSeconds = targetedSeconds
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.route = route
        self.heartRateSamples = heartRateSamples
        self.laps = laps
    }

    /// Fraction of measured target time spent on target (nil if nothing was targeted).
    public var timeInTargetFraction: Double? {
        targetedSeconds > 0 ? timeInTargetSeconds / targetedSeconds : nil
    }
}

/// Tracks a structured run from GPS samples and the clock, and decides what to say.
///
/// Pace cues: when pace (10 s average) stays outside the target range (plus tolerance) for
/// the whole cue delay, and the 20 s average agrees, one cue is spoken. The timer then restarts, so a repeat only comes
/// after another full delay still off pace. Coming back on target, or changing segment,
/// resets it. Warm-up and cool-down are quiet unless the runner opts in, and the first
/// ~15 s of each segment are ignored while the rolling average catches up.
public struct RunEngine: Sendable {
    public private(set) var config: CoachingConfig
    public let segments: [RunSegment]

    // Clock
    private var startDate: Date?
    private var activeSeconds: Double = 0
    private var lastClock: Date?
    private(set) var isPaused = false

    // Distance & samples
    private var distance: Double = 0
    private var lastSample: LocationSample?
    private var lastSampleActive: Double = 0
    /// 20 s rolling pace for display and the cue double-check.
    private var smoother: PaceSmoother
    /// Shorter window that reflects what the runner is doing now; decides "off pace".
    private var coachSmoother: PaceSmoother
    private var route: [RoutePoint] = []
    private var lastFixActive: Double?

    // Segments
    private var segmentIndex = 0
    private var segmentStartActive: Double = 0
    private var segmentStartDistance: Double = 0
    private var structureComplete = false
    /// The step's time or distance is up and it's waiting for Next step.
    private var waitingForNextStep = false
    private var segmentResults: [SegmentResult] = []
    private var segmentInTarget: Double = 0
    private var segmentMeasured: Double = 0

    // Splits
    private var splits: [Split] = []
    private var lastSplitActive: Double = 0
    private var splitHeartRates: [Double] = []

    // Manual laps
    private var laps: [Lap] = []
    private var lapStartActive: Double = 0
    private var lapStartDistance: Double = 0
    private var lapHeartRates: [Double] = []

    /// How things stood just before the last skip or lap, so it can be undone.
    private struct UndoPoint: Sendable {
        var segmentIndex: Int
        var segmentStartActive: Double
        var segmentStartDistance: Double
        var structureComplete: Bool
        var segmentResultCount: Int
        var segmentInTarget: Double
        var segmentMeasured: Double
        var lapCount: Int
        var lapStartActive: Double
        var lapStartDistance: Double
        var lapHeartRates: [Double]
        /// Segment results expected after the action (an automatic step change since then
        /// makes undo unsafe).
        var resultCountAfter: Int
        var waitingForNextStep = false
    }
    private var undoPoint: UndoPoint?

    // Coaching
    private var offDirection: PaceRange.Position?
    private var offSince: Double?
    private var lastCue: PaceCue?

    // Target & heart rate
    private var timeInTarget: Double = 0
    private var targeted: Double = 0
    private var heartRates: [Double] = []
    private var heartRateSamples: [HeartRateSample] = []
    private var currentHeartRate: Double?

    public init(structure: RunStructure?, config: CoachingConfig = CoachingConfig()) {
        self.segments = structure?.segments ?? []
        self.config = config
        self.smoother = PaceSmoother(windowSeconds: config.smoothingWindowSeconds)
        self.coachSmoother = PaceSmoother(windowSeconds: min(10, config.smoothingWindowSeconds))
    }

    public mutating func updateConfig(_ config: CoachingConfig) {
        self.config = config
        smoother.windowSeconds = config.smoothingWindowSeconds
        coachSmoother.windowSeconds = min(10, config.smoothingWindowSeconds)
    }

    private var unitLength: Double { config.units == .metric ? 1000 : Units.metersPerMile }
    private var currentSegment: RunSegment? { structureComplete || segments.isEmpty ? nil : segments[segmentIndex] }

    // MARK: - Lifecycle

    /// Starts the run. Returns the first segment announcement.
    public mutating func start(at date: Date) -> [RunEvent] {
        startDate = date
        lastClock = date
        guard let first = segments.first else { return [] }
        // Always sent (silent when step announcements are off) so the watch can still tap.
        return [.segmentStarted(index: 0, segment: first,
                                announcement: config.segmentAnnouncementsEnabled ? Announcer.segmentStart(first, units: config.units) : "")]
    }

    public mutating func pause(at date: Date) {
        advanceClock(to: date)
        isPaused = true
        resetCoach()
    }

    public mutating func resume(at date: Date) {
        lastClock = date
        isPaused = false
        // Don't count distance across the pause, or let old samples skew pace.
        lastSample = nil
        smoother.reset()
        coachSmoother.reset()
    }

    /// Moves to the next segment now (e.g. the runner taps "Skip").
    public mutating func skipSegment(at date: Date) -> [RunEvent] {
        advanceClock(to: date)
        guard currentSegment != nil else { return [] }
        let point = makeUndoPoint()
        let events = finishSegment()
        undoPoint = point
        undoPoint?.resultCountAfter = segmentResults.count
        return events
    }

    /// Whether "Next step" would skip a step (true) or there are no steps left, so the
    /// gesture marks a lap instead.
    public var hasStepToSkip: Bool { currentSegment != nil }

    /// Ends the current lap now and starts the next one. Returns the finished lap.
    @discardableResult
    public mutating func markLap(at date: Date) -> Lap {
        advanceClock(to: date)
        var point = makeUndoPoint()
        point.resultCountAfter = segmentResults.count
        let lap = Lap(index: laps.count + 1,
                      durationSeconds: activeSeconds - lapStartActive,
                      distanceMeters: distance - lapStartDistance,
                      averageHeartRate: lapHeartRates.isEmpty ? nil : lapHeartRates.reduce(0, +) / Double(lapHeartRates.count),
                      endElapsedSeconds: activeSeconds)
        laps.append(lap)
        lapStartActive = activeSeconds
        lapStartDistance = distance
        lapHeartRates.removeAll()
        undoPoint = point
        return lap
    }

    /// Whether the last skip or lap can still be undone.
    public var canUndo: Bool { undoPoint.map { $0.resultCountAfter == segmentResults.count } ?? false }

    /// Undoes the last skip or lap (time and distance since then count towards the restored
    /// step or lap). Returns false if there's nothing to undo or a step has changed since.
    @discardableResult
    public mutating func undoLastControl(at date: Date) -> Bool {
        advanceClock(to: date)
        guard let point = undoPoint, point.resultCountAfter == segmentResults.count else {
            undoPoint = nil
            return false
        }
        segmentIndex = point.segmentIndex
        segmentStartActive = point.segmentStartActive
        segmentStartDistance = point.segmentStartDistance
        structureComplete = point.structureComplete
        waitingForNextStep = point.waitingForNextStep
        segmentResults.removeLast(segmentResults.count - point.segmentResultCount)
        segmentInTarget = point.segmentInTarget + segmentInTarget
        segmentMeasured = point.segmentMeasured + segmentMeasured
        laps.removeLast(laps.count - point.lapCount)
        lapStartActive = point.lapStartActive
        lapStartDistance = point.lapStartDistance
        lapHeartRates = point.lapHeartRates + lapHeartRates
        resetCoach()
        undoPoint = nil
        return true
    }

    private func makeUndoPoint() -> UndoPoint {
        UndoPoint(segmentIndex: segmentIndex, segmentStartActive: segmentStartActive, segmentStartDistance: segmentStartDistance,
                  structureComplete: structureComplete, segmentResultCount: segmentResults.count,
                  segmentInTarget: segmentInTarget, segmentMeasured: segmentMeasured,
                  lapCount: laps.count, lapStartActive: lapStartActive, lapStartDistance: lapStartDistance,
                  lapHeartRates: lapHeartRates, resultCountAfter: segmentResults.count, waitingForNextStep: waitingForNextStep)
    }

    // MARK: - Inputs

    public mutating func addHeartRate(_ bpm: Double, at date: Date) {
        guard bpm > 30, bpm < 250 else { return }
        currentHeartRate = bpm
        if !isPaused {
            heartRates.append(bpm)
            splitHeartRates.append(bpm)
            lapHeartRates.append(bpm)
            if heartRateSamples.last.map({ activeSeconds - $0.elapsed >= 5 }) ?? true {
                heartRateSamples.append(HeartRateSample(elapsed: activeSeconds, bpm: bpm))
            }
        }
    }

    /// Feeds a GPS sample. Inaccurate or implausible fixes are ignored.
    public mutating func addLocation(_ sample: LocationSample) -> [RunEvent] {
        guard startDate != nil else { return [] }
        var events = advanceClock(to: sample.timestamp)
        guard !isPaused, sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 30 else { return events }

        if let previous = lastSample {
            let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { return events }
            let step = Geo.distance(previous.latitude, previous.longitude, sample.latitude, sample.longitude)
            // Ignore teleports (faster than ~12 m/s, i.e. a sub-1:30/km sprint).
            guard step / dt <= 12 else { return events }
            let before = distance
            distance += step
            events += recordSplits(from: before, to: distance, fromActive: lastSampleActive, toActive: activeSeconds)
        }
        lastSample = sample
        lastSampleActive = activeSeconds
        lastFixActive = activeSeconds
        smoother.add(time: activeSeconds, distance: distance, speed: sample.speed)
        coachSmoother.add(time: activeSeconds, distance: distance, speed: sample.speed)
        route.append(RoutePoint(latitude: sample.latitude, longitude: sample.longitude, elapsed: activeSeconds, altitude: sample.altitude))

        events += progressSegments()
        events += evaluateCoach()
        return events
    }

    /// Call about once a second so time-based segments advance even without GPS.
    public mutating func tick(at date: Date) -> [RunEvent] {
        var events = advanceClock(to: date)
        events += progressSegments()
        events += evaluateCoach()
        return events
    }

    // MARK: - Outputs

    public func snapshot() -> RunSnapshot {
        let segment = currentSegment
        var progress = 0.0
        var remaining: SegmentLength?
        if let segment {
            switch segment.length {
            case .duration(let seconds):
                let done = activeSeconds - segmentStartActive
                progress = seconds > 0 ? done / seconds : 1
                remaining = .duration(seconds: max(0, seconds - done))
            case .distance(let meters):
                let done = distance - segmentStartDistance
                progress = meters > 0 ? done / meters : 1
                remaining = .distance(meters: max(0, meters - done))
            }
        }
        let pace = gpsFresh ? smoother.pace : nil
        return RunSnapshot(
            elapsedSeconds: activeSeconds,
            distanceMeters: distance,
            currentPace: pace,
            averagePace: averagePace,
            segmentIndex: segment == nil ? nil : segmentIndex,
            segment: segment,
            nextSegment: segment == nil || segmentIndex + 1 >= segments.count ? nil : segments[segmentIndex + 1],
            segmentProgress: min(max(progress, 0), 1),
            segmentRemaining: remaining,
            // An effort-guided step shows its pace as a guide, without on/off target colours.
            paceStatus: segment?.paceIsGuide == true ? nil
                : pace.flatMap { p in segment?.targetPace.map { $0.position(of: p, toleranceSecondsPerKm: config.toleranceSecondsPerKm) } },
            timeInTargetSeconds: timeInTarget,
            targetedSeconds: targeted,
            heartRate: currentHeartRate,
            isPaused: isPaused,
            isStructureComplete: structureComplete || segments.isEmpty,
            lastCue: lastCue,
            gpsAvailable: gpsFresh,
            lapNumber: laps.isEmpty ? nil : laps.count + 1,
            lapElapsedSeconds: laps.isEmpty ? nil : activeSeconds - lapStartActive,
            lapDistanceMeters: laps.isEmpty ? nil : distance - lapStartDistance,
            lastLap: laps.last,
            isWaitingForNextStep: waitingForNextStep ? true : nil
        )
    }

    public func summary() -> RunSummary {
        var results = segmentResults
        if let segment = currentSegment, activeSeconds > segmentStartActive {
            results.append(currentSegmentResult(segment))
        }
        return RunSummary(
            durationSeconds: activeSeconds,
            distanceMeters: distance,
            averagePace: averagePace,
            splits: splits,
            segments: results,
            timeInTargetSeconds: timeInTarget,
            targetedSeconds: targeted,
            averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
            maxHeartRate: heartRates.max(),
            route: route,
            heartRateSamples: heartRateSamples,
            laps: summaryLaps
        )
    }

    /// The marked laps plus the one in progress (so the last stretch isn't lost).
    private var summaryLaps: [Lap]? {
        guard !laps.isEmpty else { return nil }
        var all = laps
        if activeSeconds - lapStartActive >= 1 {
            all.append(Lap(index: laps.count + 1, durationSeconds: activeSeconds - lapStartActive,
                           distanceMeters: distance - lapStartDistance,
                           averageHeartRate: lapHeartRates.isEmpty ? nil : lapHeartRates.reduce(0, +) / Double(lapHeartRates.count),
                           endElapsedSeconds: activeSeconds))
        }
        return all
    }

    // MARK: - Internals

    private var averagePace: Pace? {
        guard distance > 50, activeSeconds > 0 else { return nil }
        return Pace(metersPerSecond: distance / activeSeconds)
    }

    /// GPS counts as live if a usable fix arrived in the last 10 seconds.
    private var gpsFresh: Bool {
        guard let last = lastFixActive else { return false }
        return activeSeconds - last <= 10
    }

    /// Advances active time, accruing time-in-target. Returns no events itself
    /// (kept as a hook so callers can chain).
    @discardableResult
    private mutating func advanceClock(to date: Date) -> [RunEvent] {
        guard let last = lastClock else { lastClock = date; return [] }
        let dt = date.timeIntervalSince(last)
        guard dt > 0 else { return [] }
        lastClock = date
        guard !isPaused else { return [] }
        activeSeconds += dt

        if let target = currentSegment?.targetPace, let kind = currentSegment?.kind, currentSegment?.paceIsGuide != true,
           kind == .work || kind == .steady, gpsFresh, let pace = smoother.pace {
            targeted += dt
            segmentMeasured += dt
            if target.position(of: pace, toleranceSecondsPerKm: config.toleranceSecondsPerKm) == .onTarget {
                timeInTarget += dt
                segmentInTarget += dt
            }
        }
        return []
    }

    private mutating func progressSegments() -> [RunEvent] {
        var events: [RunEvent] = []
        // Loop in case a short segment was passed entirely between updates.
        while let segment = currentSegment {
            let done: Bool
            switch segment.length {
            case .duration(let seconds): done = activeSeconds - segmentStartActive >= seconds
            case .distance(let meters): done = distance - segmentStartDistance >= meters
            }
            guard done else { break }
            // Steps that don't move on by themselves: say so once and wait for Next step (the
            // last step still finishes the session).
            if !config.advancesStepsAutomatically, segmentIndex + 1 < segments.count {
                if !waitingForNextStep {
                    waitingForNextStep = true
                    let next = segments[segmentIndex + 1]
                    events.append(.stepEnded(index: segmentIndex, next: next,
                                             announcement: config.segmentAnnouncementsEnabled
                                                ? Announcer.stepEnded(segment, next: next, units: config.units) : ""))
                }
                break
            }
            events += finishSegment()
        }
        return events
    }

    private mutating func finishSegment() -> [RunEvent] {
        guard let segment = currentSegment else { return [] }
        segmentResults.append(currentSegmentResult(segment))
        segmentInTarget = 0
        segmentMeasured = 0
        resetCoach()

        if waitingForNextStep {
            // Started by hand after waiting: the next step starts now.
            segmentStartActive = activeSeconds
            segmentStartDistance = distance
            waitingForNextStep = false
        } else {
            // Start the next segment where this one should have ended (keeps boundaries exact).
            switch segment.length {
            case .duration(let seconds): segmentStartActive = min(activeSeconds, segmentStartActive + seconds)
            case .distance: segmentStartActive = activeSeconds
            }
            switch segment.length {
            case .distance(let meters): segmentStartDistance = min(distance, segmentStartDistance + meters)
            case .duration: segmentStartDistance = distance
            }
        }

        if segmentIndex + 1 < segments.count {
            segmentIndex += 1
            let next = segments[segmentIndex]
            return [.segmentStarted(index: segmentIndex, segment: next,
                                    announcement: config.segmentAnnouncementsEnabled
                                        ? Announcer.segmentStart(next, units: config.units, after: segment) : "")]
        }
        structureComplete = true
        return [.workoutComplete(announcement: Announcer.workoutComplete)]
    }

    private func currentSegmentResult(_ segment: RunSegment) -> SegmentResult {
        let duration = activeSeconds - segmentStartActive
        let meters = distance - segmentStartDistance
        return SegmentResult(
            index: segmentIndex,
            segment: segment,
            durationSeconds: duration,
            distanceMeters: meters,
            averagePace: meters > 20 && duration > 0 ? Pace(metersPerSecond: meters / duration) : nil,
            secondsInTarget: segmentInTarget,
            secondsMeasured: segmentMeasured
        )
    }

    private mutating func recordSplits(from before: Double, to after: Double, fromActive: Double, toActive: Double) -> [RunEvent] {
        var events: [RunEvent] = []
        var boundary = (floor(before / unitLength) + 1) * unitLength
        while boundary <= after {
            // Interpolate when the boundary was crossed.
            let fraction = after > before ? (boundary - before) / (after - before) : 1
            let crossing = fromActive + (toActive - fromActive) * fraction
            let duration = crossing - lastSplitActive
            lastSplitActive = crossing
            let index = splits.count + 1
            let split = Split(
                index: index,
                durationSeconds: duration,
                pace: Pace(secondsPerKm: duration / unitLength * 1000),
                averagePace: Pace(secondsPerKm: crossing / boundary * 1000),
                averageHeartRate: splitHeartRates.isEmpty ? nil : splitHeartRates.reduce(0, +) / Double(splitHeartRates.count)
            )
            splitHeartRates.removeAll()
            splits.append(split)
            if config.splitAnnouncementsEnabled {
                events.append(.split(split, announcement: Announcer.split(split, units: config.units)))
            }
            boundary += unitLength
        }
        return events
    }

    private mutating func resetCoach() {
        offDirection = nil
        offSince = nil
    }

    private mutating func evaluateCoach() -> [RunEvent] {
        guard config.paceCuesEnabled, !isPaused, let segment = currentSegment, let target = segment.targetPace,
              segment.paceIsGuide != true,
              config.cuesDuringWarmUpCoolDown || !segment.kind.isEasyBookend,
              gpsFresh, let pace = coachSmoother.pace
        else {
            resetCoach()
            return []
        }
        // Right after a segment change the smoothed pace still includes the previous
        // segment (e.g. the recovery jog), so wait until the window is mostly in this one.
        guard activeSeconds - segmentStartActive >= config.smoothingWindowSeconds * 0.75 else {
            resetCoach()
            return []
        }
        let position = target.position(of: pace, toleranceSecondsPerKm: config.toleranceSecondsPerKm)
        guard position != .onTarget else {
            resetCoach()
            return []
        }
        guard position == offDirection, let since = offSince else {
            offDirection = position
            offSince = activeSeconds
            return []
        }
        guard activeSeconds - since >= config.paceCueDelaySeconds else { return [] }
        // Double-check with the longer average so GPS noise can't trigger a cue.
        guard let steadyPace = smoother.pace,
              target.position(of: steadyPace, toleranceSecondsPerKm: config.toleranceSecondsPerKm) == position
        else { return [] }
        // Cue, then require another full delay off pace before repeating.
        offSince = activeSeconds
        let cue = PaceCue(direction: position, pace: steadyPace, target: target,
                          message: Announcer.paceCue(position, target: target, units: config.units))
        lastCue = cue
        return [.paceCue(cue)]
    }
}
