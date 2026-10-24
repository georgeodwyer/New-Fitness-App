import Foundation

// A run recorded on the iPhone and shown live on the Apple Watch ("mirrored"). The phone
// does the GPS, coaching and saving; the watch shows the run screen, taps the wrist, sends
// its buttons back and adds live heart rate. Like `WatchPlan`, these are plain JSON and new
// fields must be optional so a phone and watch on different app versions still understand
// each other.

/// A message between the phone and the watch during a mirrored run.
public enum MirrorMessage: Codable, Equatable, Sendable {
    /// Phone → watch: the run screen right now (about once a second, and straight away
    /// when something happens).
    case frame(MirrorFrame)
    /// Phone → watch: the run is over (finished or thrown away) and the watch can stop.
    case ended(runId: UUID?, saved: Bool)
    /// Watch → phone: a button pressed on the watch.
    case command(MirrorCommand)
    /// Watch → phone: a live heart-rate reading.
    case heartRate(bpm: Double, at: Date)

    public func encoded() -> Data { (try? WatchCoding.encoder.encode(self)) ?? Data() }
    public static func decode(_ data: Data) -> MirrorMessage? { try? WatchCoding.decoder.decode(MirrorMessage.self, from: data) }
}

/// Buttons on the watch that control the phone's run.
public enum MirrorCommand: String, Codable, Sendable {
    case pause, resume, skipStep, end
    /// Marks a lap (a run without steps left).
    case lap
    /// Undoes the last skip or lap.
    case undo
}

/// What the watch should tap the wrist for.
public enum MirrorAlert: String, Codable, Sendable {
    /// Running too slowly for the target.
    case speedUp
    /// Running too fast for the target.
    case easeOff
    /// A new step of the session has started.
    case newStep
    /// Another kilometre or mile done.
    case split
    /// The structured part of the session is done.
    case complete

    /// The tap for something the run engine announced.
    public init(event: RunEvent) {
        switch event {
        case .paceCue(let cue): self = cue.direction == .tooSlow ? .speedUp : .easeOff
        case .segmentStarted: self = .newStep
        case .split: self = .split
        case .workoutComplete: self = .complete
        }
    }
}

/// The phone's run screen, for the watch to show.
public struct MirrorFrame: Codable, Equatable, Sendable {
    /// The phone's run (so a frame from an old run is never mistaken for the current one).
    public var runId: UUID
    public var title: String
    public var units: UnitSystem
    /// The run has steps (reps, warm-up, …) rather than being a free run.
    public var isStructured: Bool
    public var snapshot: RunSnapshot
    /// Taps for what happened since the last frame.
    public var alerts: [MirrorAlert]
    public var sentAt: Date

    public init(runId: UUID, title: String, units: UnitSystem, isStructured: Bool, snapshot: RunSnapshot,
                alerts: [MirrorAlert] = [], sentAt: Date) {
        self.runId = runId
        self.title = title
        self.units = units
        self.isStructured = isStructured
        var snapshot = snapshot
        // The watch only needs the tap, not the cue's details.
        snapshot.lastCue = nil
        self.snapshot = snapshot
        self.alerts = alerts
        self.sentAt = sentAt
    }

    /// Recent enough to show (or to start showing) on the watch.
    public func isFresh(at now: Date, maxAgeSeconds: Double = 15) -> Bool {
        now.timeIntervalSince(sentAt) <= maxAgeSeconds
    }
}
