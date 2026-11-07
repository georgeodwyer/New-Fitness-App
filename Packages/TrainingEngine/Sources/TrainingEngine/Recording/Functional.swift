import Foundation

// MARK: - The workout

/// A functional (circuit / Hyrox-style) workout: stations done in rounds for time, by the
/// clock (intervals, EMOM) or as many rounds as possible (AMRAP).
public struct FunctionalWorkout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var format: FunctionalFormat
    public var stations: [FunctionalStation]

    public init(id: UUID = UUID(), name: String, format: FunctionalFormat = .rounds(3), stations: [FunctionalStation] = []) {
        self.id = id
        self.name = name
        self.format = format
        self.stations = stations
    }

    /// "4 rounds · 3 stations", "EMOM 20 min", "AMRAP 20 min"…
    public var summary: String {
        let count = "\(stations.count) station\(stations.count == 1 ? "" : "s")"
        switch format {
        case .rounds(let rounds): return "\(rounds) round\(rounds == 1 ? "" : "s") for time · \(count)"
        case .intervals(let work, let rest, let rounds):
            return "\(rounds) × \(Int(work)) s on / \(Int(rest)) s off · \(count)"
        case .emom(let every, let rounds):
            return every == 60 ? "EMOM \(rounds) min · \(count)" : "Every \(Int(every)) s × \(rounds) · \(count)"
        case .amrap(let cap): return "AMRAP \(Int(cap / 60)) min · \(count)"
        }
    }
}

public enum FunctionalFormat: Codable, Equatable, Sendable {
    /// Every station in order, this many times, as fast as you can.
    case rounds(Int)
    /// Each station gets `work` seconds, then `rest`; the whole list `rounds` times.
    case intervals(work: Double, rest: Double, rounds: Int)
    /// A new station starts every `every` seconds (60 = every minute), `rounds` times.
    case emom(every: Double, rounds: Int)
    /// As many rounds of the stations as possible in `cap` seconds.
    case amrap(cap: Double)

    public var displayName: String {
        switch self {
        case .rounds: return "Rounds for time"
        case .intervals: return "Intervals"
        case .emom: return "EMOM"
        case .amrap: return "AMRAP"
        }
    }
}

/// How hard a run station is: a pace you set, or one of your training paces (it follows your fitness).
public enum FunctionalPace: Codable, Equatable, Hashable, Sendable {
    case fixed(PaceTarget)
    case zone(PaceZone)

    public func range(zones: PaceZones) -> PaceRange {
        switch self {
        case .fixed(let target): return target.range
        case .zone(let zone): return zones.range(for: zone)
        }
    }
}

/// What a station asks for.
public enum FunctionalTarget: Codable, Equatable, Hashable, Sendable {
    case meters(Double)
    case calories(Int)
    case reps(Int)
    case seconds(Double)

    /// "1,000 m", "15 cal", "20 reps", "1 min".
    public var text: String {
        switch self {
        case .meters(let m): return m >= 1000 && m.truncatingRemainder(dividingBy: 1000) == 0 ? "\(Int(m / 1000)) km" : "\(Int(m)) m"
        case .calories(let c): return "\(c) cal"
        case .reps(let r): return "\(r) reps"
        case .seconds(let s):
            if s >= 60 && s.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(s / 60)) min" }
            return s >= 60 ? "\(Int(s) / 60) min \(Int(s) % 60) s" : "\(Int(s)) s"
        }
    }
}

public struct FunctionalStation: Codable, Equatable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case run, ski, row, bike, sledPush, sledPull, burpeeBroadJumps, farmersCarry, sandbagLunges, wallBalls, exercise, rest

        public var displayName: String {
            switch self {
            case .run: return "Run"
            case .ski: return "SkiErg"
            case .row: return "Row"
            case .bike: return "Bike"
            case .sledPush: return "Sled push"
            case .sledPull: return "Sled pull"
            case .burpeeBroadJumps: return "Burpee broad jumps"
            case .farmersCarry: return "Farmers carry"
            case .sandbagLunges: return "Sandbag lunges"
            case .wallBalls: return "Wall balls"
            case .exercise: return "Exercise"
            case .rest: return "Rest"
            }
        }

        /// What it's usually measured in.
        public var defaultTarget: FunctionalTarget {
            switch self {
            case .run: return .meters(1000)
            case .ski, .row: return .meters(1000)
            case .bike: return .calories(20)
            case .sledPush, .sledPull: return .meters(50)
            case .burpeeBroadJumps: return .meters(80)
            case .farmersCarry: return .meters(200)
            case .sandbagLunges: return .meters(100)
            case .wallBalls: return .reps(100)
            case .exercise: return .reps(10)
            case .rest: return .seconds(60)
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// For `.exercise`: the exercise from the library (any gym exercise).
    public var exerciseId: String?
    /// Shown name (the kind's name unless it's a named exercise).
    public var name: String
    public var target: FunctionalTarget
    public var weightKg: Double?
    /// Runs: the pace to hold (nil = by feel).
    public var pace: FunctionalPace?
    /// Runs: on a treadmill (time only, no GPS; the pace shows as a treadmill speed).
    public var treadmill: Bool

    public init(id: UUID = UUID(), kind: Kind, exerciseId: String? = nil, name: String? = nil, target: FunctionalTarget? = nil,
                weightKg: Double? = nil, pace: FunctionalPace? = nil, treadmill: Bool = false) {
        self.id = id
        self.kind = kind
        self.exerciseId = exerciseId
        self.name = name ?? kind.displayName
        self.target = target ?? kind.defaultTarget
        self.weightKg = weightKg
        self.pace = pace
        self.treadmill = treadmill
    }

    /// "Run 1 km", "Wall balls 20 reps · 6 kg".
    public var title: String { "\(name) \(target.text)" }
}

// MARK: - Hyrox simulation

public enum HyroxSimulation {
    /// The race: 8 × (1 km run + a station) in race order, at the division's weights.
    public static func workout(division: HyroxDivision = .openMen, treadmill: Bool = false) -> FunctionalWorkout {
        let pro = division == .proMen || division == .proWomen
        let men = division == .openMen || division == .proMen
        func weight(openWomen: Double, openMen: Double, proWomen: Double, proMen: Double) -> Double {
            pro ? (men ? proMen : proWomen) : (men ? openMen : openWomen)
        }
        let stations: [FunctionalStation] = [
            .init(kind: .ski, target: .meters(1000)),
            .init(kind: .sledPush, target: .meters(50), weightKg: weight(openWomen: 102, openMen: 152, proWomen: 152, proMen: 202)),
            .init(kind: .sledPull, target: .meters(50), weightKg: weight(openWomen: 78, openMen: 103, proWomen: 103, proMen: 153)),
            .init(kind: .burpeeBroadJumps, target: .meters(80)),
            .init(kind: .row, target: .meters(1000)),
            .init(kind: .farmersCarry, target: .meters(200), weightKg: weight(openWomen: 16, openMen: 24, proWomen: 24, proMen: 32)),
            .init(kind: .sandbagLunges, target: .meters(100), weightKg: weight(openWomen: 10, openMen: 20, proWomen: 20, proMen: 30)),
            .init(kind: .wallBalls, target: .reps(100), weightKg: weight(openWomen: 4, openMen: 6, proWomen: 6, proMen: 9))
        ]
        var all: [FunctionalStation] = []
        for station in stations {
            all.append(.init(kind: .run, target: .meters(1000), treadmill: treadmill))
            all.append(station)
        }
        return FunctionalWorkout(name: "Hyrox simulation", format: .rounds(1), stations: all)
    }
}

// MARK: - Doing it

/// One station done: when, how long, and (for runs) how far.
public struct FunctionalSplit: Codable, Equatable, Sendable {
    public var round: Int
    public var stationIndex: Int
    public var name: String
    public var kind: FunctionalStation.Kind
    public var seconds: Double
    public var meters: Double?
    public var target: FunctionalTarget

    public init(round: Int, stationIndex: Int, name: String, kind: FunctionalStation.Kind, seconds: Double, meters: Double? = nil,
                target: FunctionalTarget) {
        self.round = round
        self.stationIndex = stationIndex
        self.name = name
        self.kind = kind
        self.seconds = seconds
        self.meters = meters
        self.target = target
    }
}

/// The workout as it happens: which round and station, work or rest, and the splits so far.
/// Rounds for time and AMRAP move on when you tap Next (timed stations and rests by themselves);
/// intervals and EMOM move on by the clock.
public struct FunctionalSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case work, rest }

    public let workout: FunctionalWorkout
    public private(set) var startedAt: Date
    public private(set) var round = 1
    public private(set) var stationIndex = 0
    public private(set) var phase: Phase = .work
    /// When the current station (or rest) started.
    public private(set) var phaseStartedAt: Date
    public private(set) var splits: [FunctionalSplit] = []
    public private(set) var isFinished = false
    /// Station done early in EMOM: waiting for the next interval.
    public private(set) var isWaitingForInterval = false
    private var history: [FunctionalSession.Snapshot] = []

    private struct Snapshot: Equatable, Sendable {
        var round: Int, stationIndex: Int, phase: Phase, phaseStartedAt: Date, splitCount: Int, finished: Bool, waiting: Bool
    }

    public init(workout: FunctionalWorkout, startedAt: Date) {
        self.workout = workout
        self.startedAt = startedAt
        self.phaseStartedAt = startedAt
        if workout.stations.isEmpty { isFinished = true }
    }

    public var station: FunctionalStation? { isFinished ? nil : workout.stations[safe: stationIndex] }

    /// The station after this one (in the next round if this is the last).
    public var nextStation: FunctionalStation? {
        guard !isFinished, !workout.stations.isEmpty else { return nil }
        let next = stationIndex + 1
        if next < workout.stations.count { return workout.stations[next] }
        return round < totalRounds ?? Int.max ? workout.stations.first : nil
    }

    /// Rounds in the workout (nil for AMRAP).
    public var totalRounds: Int? {
        switch workout.format {
        case .rounds(let rounds): return max(rounds, 1)
        case .intervals(_, _, let rounds): return max(rounds, 1)
        case .emom(_, let rounds): return max(1, Int((Double(rounds) / Double(max(workout.stations.count, 1))).rounded(.up)))
        case .amrap: return nil
        }
    }

    /// AMRAP: whole rounds done.
    public var roundsDone: Int { splits.isEmpty ? 0 : (round - 1) }

    public func elapsed(at now: Date) -> Double { max(0, now.timeIntervalSince(startedAt)) }
    public func phaseElapsed(at now: Date) -> Double { max(0, now.timeIntervalSince(phaseStartedAt)) }

    /// Seconds left in the current work/rest window (clock formats, rest stations), or the AMRAP cap.
    public func remaining(at now: Date) -> Double? {
        switch workout.format {
        case .intervals(let work, let rest, _):
            return max(0, (phase == .work ? work : rest) - phaseElapsed(at: now))
        case .emom(let every, _):
            return max(0, every - phaseElapsed(at: now))
        case .amrap(let cap):
            return max(0, cap - elapsed(at: now))
        case .rounds:
            if let seconds = timedStationSeconds {
                return max(0, seconds - phaseElapsed(at: now))
            }
            return nil
        }
    }

    /// Next (tap, double tap or the crown): this station is done.
    public mutating func next(at now: Date, meters: Double? = nil) {
        guard !isFinished else { return }
        history.append(snapshot())
        switch workout.format {
        case .rounds, .amrap:
            recordSplit(at: now, meters: meters)
            advanceStation(at: now)
        case .intervals:
            if phase == .work {
                recordSplit(at: now, meters: meters)
                startRest(at: now)
            } else {
                advanceStation(at: now)
            }
        case .emom:
            if !isWaitingForInterval {
                recordSplit(at: now, meters: meters)
                isWaitingForInterval = true
            }
        }
        if case .amrap(let cap) = workout.format, elapsed(at: now) >= cap { isFinished = true }
    }

    /// Call about once a second: moves on when the clock says so. Returns true if something changed.
    @discardableResult
    public mutating func tick(at now: Date, meters: Double? = nil) -> Bool {
        guard !isFinished else { return false }
        switch workout.format {
        case .intervals(let work, let rest, _):
            if phase == .work, phaseElapsed(at: now) >= work {
                let end = phaseStartedAt.addingTimeInterval(work)
                recordSplit(at: end, meters: meters)
                startRest(at: end)
                return true
            }
            if phase == .rest, phaseElapsed(at: now) >= rest {
                advanceStation(at: phaseStartedAt.addingTimeInterval(rest))
                return true
            }
        case .emom(let every, let rounds):
            if phaseElapsed(at: now) >= every {
                let end = phaseStartedAt.addingTimeInterval(every)
                if !isWaitingForInterval { recordSplit(at: end, meters: meters) }
                isWaitingForInterval = false
                if splits.count >= rounds {
                    isFinished = true
                } else {
                    stationIndex = (stationIndex + 1) % workout.stations.count
                    if stationIndex == 0 { round += 1 }
                    phaseStartedAt = end
                }
                return true
            }
        case .amrap(let cap):
            if elapsed(at: now) >= cap {
                isFinished = true
                return true
            }
            if let seconds = timedStationSeconds, phaseElapsed(at: now) >= seconds {
                recordSplit(at: phaseStartedAt.addingTimeInterval(seconds), meters: meters)
                advanceStation(at: phaseStartedAt.addingTimeInterval(seconds))
                return true
            }
        case .rounds:
            if let seconds = timedStationSeconds, phaseElapsed(at: now) >= seconds {
                recordSplit(at: phaseStartedAt.addingTimeInterval(seconds), meters: meters)
                advanceStation(at: phaseStartedAt.addingTimeInterval(seconds))
                return true
            }
        }
        return false
    }

    /// A station done for time ("plank 1 min", "run 2 min", rest) moves on by itself when the
    /// time is up (rounds for time and AMRAP; the clock formats time every station anyway).
    public var timedStationSeconds: Double? {
        guard let station, case .seconds(let seconds) = station.target else { return nil }
        return seconds
    }

    public var canUndo: Bool { !history.isEmpty }

    /// Takes back the last Next (the station carries on from when it started).
    public mutating func undo() {
        guard let last = history.popLast() else { return }
        round = last.round
        stationIndex = last.stationIndex
        phase = last.phase
        phaseStartedAt = last.phaseStartedAt
        splits.removeLast(max(0, splits.count - last.splitCount))
        isFinished = last.finished
        isWaitingForInterval = last.waiting
    }

    /// Stop now (the station under way is recorded as far as it got).
    public mutating func finish(at now: Date, meters: Double? = nil) {
        guard !isFinished else { return }
        if phase == .work && !isWaitingForInterval { recordSplit(at: now, meters: meters) }
        isFinished = true
    }

    // MARK: Steps

    private func snapshot() -> Snapshot {
        Snapshot(round: round, stationIndex: stationIndex, phase: phase, phaseStartedAt: phaseStartedAt, splitCount: splits.count,
                 finished: isFinished, waiting: isWaitingForInterval)
    }

    private mutating func recordSplit(at now: Date, meters: Double?) {
        guard let station else { return }
        splits.append(FunctionalSplit(round: round, stationIndex: stationIndex, name: station.name, kind: station.kind,
                                      seconds: max(0, now.timeIntervalSince(phaseStartedAt)), meters: meters, target: station.target))
    }

    private mutating func startRest(at now: Date) {
        phase = .rest
        phaseStartedAt = now
    }

    private mutating func advanceStation(at now: Date) {
        phase = .work
        phaseStartedAt = now
        if stationIndex + 1 < workout.stations.count {
            stationIndex += 1
            return
        }
        if let total = totalRounds, round >= total {
            isFinished = true
            return
        }
        round += 1
        stationIndex = 0
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Done

/// A finished functional workout, as saved: what it was and how each station went.
public struct FunctionalRecord: Codable, Equatable, Sendable {
    public var workout: FunctionalWorkout
    public var splits: [FunctionalSplit]
    /// AMRAP: whole rounds done.
    public var roundsDone: Int
    /// Run stations' GPS distance added up (outdoor runs only).
    public var runMeters: Double

    public init(workout: FunctionalWorkout, splits: [FunctionalSplit], roundsDone: Int, runMeters: Double) {
        self.workout = workout
        self.splits = splits
        self.roundsDone = roundsDone
        self.runMeters = runMeters
    }

    public init(session: FunctionalSession) {
        self.init(workout: session.workout, splits: session.splits, roundsDone: session.roundsDone,
                  runMeters: session.splits.compactMap(\.meters).reduce(0, +))
    }

    /// Time spent on each kind of station (runs, SkiErg, sled…), largest first. Rests left out.
    public var timeByKind: [(kind: FunctionalStation.Kind, seconds: Double)] {
        var totals: [FunctionalStation.Kind: Double] = [:]
        for split in splits where split.kind != .rest { totals[split.kind, default: 0] += split.seconds }
        return totals.map { ($0.key, $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    /// "Run 1 km  4:12" lines, one per station, for Strava and sharing.
    public func lines() -> [String] {
        splits.filter { $0.kind != .rest }.map { split in
            let round = (workout.stations.count > 1 && splits.contains { $0.round > 1 }) ? "R\(split.round) " : ""
            return "\(round)\(split.name) \(split.target.text)  \(Units.formatMinutesSeconds(split.seconds))"
        }
    }
}

extension Pace {
    /// Treadmill speed for this pace, km/h (one decimal).
    public var kilometresPerHour: Double { secondsPerKm > 0 ? (36_000 / secondsPerKm).rounded() / 10 : 0 }
}
