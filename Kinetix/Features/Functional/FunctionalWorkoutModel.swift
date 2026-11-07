import Foundation
import Observation
import SwiftData
import HealthKit
import UIKit
import TrainingEngine

/// A functional workout as it happens: the station clock, Next/undo, heart rate, and for
/// outdoor run stations the GPS distance and pace against the target (with voice cues).
@Observable
@MainActor
final class FunctionalWorkoutModel {
    private(set) var session: FunctionalSession
    let units: UnitSystem
    /// The runner's training paces, for run stations set to a training pace.
    let paceZones: PaceZones?
    let heartRateZones: HeartRateZones
    /// The saved workout it came from, if any.
    let templateId: UUID?
    private let context: ModelContext

    /// Updated every half second so the clocks move.
    private(set) var now = Date()
    /// Finished and waiting for "how hard was it?" (nil while under way).
    private(set) var record: FunctionalRecord?
    private(set) var savedLog: StrengthLogModel?

    // Heart rate
    private(set) var heartRate: Double?
    private(set) var heartRateAt: Date?
    private(set) var maxHeartRate: Double?
    @ObservationIgnored private let healthStore = HKHealthStore()
    @ObservationIgnored private var healthQuery: HKAnchoredObjectQuery?
    @ObservationIgnored private var lastStrapAt: Date?

    // GPS (outdoor run stations)
    @ObservationIgnored private var gps: GPSLocationSource?
    @ObservationIgnored private var lastSample: LocationSample?
    /// Metres run in the current station.
    private(set) var stationMeters: Double = 0
    /// (time, metres so far in the station), for the current pace.
    @ObservationIgnored private var trail: [(at: Date, meters: Double)] = []
    private(set) var currentPace: Pace?
    private(set) var hasGPSFix = false

    // Cues
    @ObservationIgnored private let voice = VoiceCoach()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var announcedStationKey = ""
    @ObservationIgnored private var lastPaceCueAt: Date?
    @ObservationIgnored private var targetReachedKey = ""
    @ObservationIgnored private let paceTolerance: Double
    @ObservationIgnored private let paceCuesEnabled: Bool

    init(workout: FunctionalWorkout, templateId: UUID?, units: UnitSystem, settings: CoachingSettingsModel?, context: ModelContext) {
        let start = Date()
        self.session = FunctionalSession(workout: workout, startedAt: start)
        self.units = units
        self.templateId = templateId
        self.context = context
        let profile = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.profile
        self.paceZones = profile.map { PaceZones(profile: $0) }
        let runs = (try? context.fetch(FetchDescriptor<RunLogModel>())) ?? []
        self.heartRateZones = StrainService.zones(profile: profile, runs: runs)
        self.paceTolerance = settings?.paceToleranceSecondsPerKm ?? 5
        self.paceCuesEnabled = settings?.paceCuesEnabled ?? true
        voice.voiceIdentifier = settings?.voiceIdentifier
        voice.volume = Float(settings?.cueVolume ?? 1)
        voice.prepare()
        now = start
        startHeartRate()
        if workout.stations.contains(where: { $0.kind == .run && !$0.treadmill }) { startGPS() }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        announceStation()
        startWatch()
    }

    // MARK: Apple Watch

    /// Showing on the Apple Watch (the Kinetix watch app, recording heart rate).
    private(set) var isOnWatch = false
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var lastWatchHeartRateAt: Date?
    /// Taps for the watch since the last frame.
    @ObservationIgnored private var pendingAlerts: [MirrorAlert] = []
    /// One id for the watch link for the whole session.
    @ObservationIgnored private let watchSessionId = UUID()

    private func startWatch() {
        let handlers = WatchMirrorService.Handlers(
            command: { [weak self] command in self?.handleWatch(command) },
            heartRate: { [weak self] bpm, _ in self?.receiveWatchHeartRate(bpm) },
            resync: { [weak self] in self?.publishToWatch() }
        )
        isOnWatch = WatchMirrorService.shared.begin(runId: watchSessionId, handlers: handlers, activity: .functionalStrengthTraining)
        guard isOnWatch else { return }
        publishToWatch()
        // The watch treats silence as a lost phone, so keep it up to date between changes.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishToWatch() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func handleWatch(_ command: MirrorCommand) {
        switch command {
        case .next, .skipStep, .lap:
            guard !session.isFinished, !session.isWaitingForInterval else { publishToWatch(); return }
            next()
        case .undo:
            guard session.canUndo else { publishToWatch(); return }
            undo()
        default:
            break
        }
    }

    private func receiveWatchHeartRate(_ bpm: Double) {
        lastWatchHeartRateAt = Date()
        receiveHeartRate(bpm, strap: false, live: true)
    }

    /// "Round 2 of 4 · Station 3 of 8".
    var progressText: String {
        let station = "Station \(session.stationIndex + 1) of \(workout.stations.count)"
        if case .amrap = workout.format { return "Round \(session.round) · \(station)" }
        if let total = session.totalRounds, total > 1 { return "Round \(session.round) of \(total) · \(station)" }
        return station
    }

    private func publishToWatch() {
        guard isOnWatch else { return }
        let date = Date()
        let station = session.station
        var detail: [String] = []
        if let station {
            detail.append(station.target.text)
            if let kg = station.weightKg, kg > 0 { detail.append(DisplayFormat(units: units).weight(kg)) }
            if let speed = treadmillSpeed(for: station) {
                detail.append(speed)
            } else if let range = paceRange(for: station) {
                detail.append(Units.formatPace(range.fastest, units: units) + Units.paceUnitLabel(units))
            }
        }
        let phaseLabel: String? = session.isFinished ? nil
            : (session.phase == .rest ? "Rest" : (session.isWaitingForInterval ? "Done · wait" : nil))
        let remaining = session.remaining(at: date)
        let frame = FunctionalMirrorFrame(
            sessionId: watchSessionId,
            title: workout.name,
            station: station?.name,
            detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
            progress: progressText,
            phaseLabel: phaseLabel,
            clockStartedAt: remaining == nil ? session.phaseStartedAt : nil,
            clockEndsAt: remaining.map { date.addingTimeInterval($0) },
            startedAt: session.startedAt,
            next: session.nextStation?.title,
            meters: isOutdoorRun ? stationMeters : nil,
            currentPace: isOutdoorRun ? currentPace : nil,
            pacePosition: pacePosition,
            canUndo: session.canUndo,
            nextDisabled: session.isWaitingForInterval,
            isFinished: session.isFinished,
            units: units,
            alerts: pendingAlerts,
            zoneStarts: heartRateZones.starts,
            maxHeartRate: heartRateZones.maxHeartRate,
            sentAt: date
        )
        pendingAlerts = []
        WatchMirrorService.shared.publish(frame)
    }

    private func alertWatch(_ alert: MirrorAlert) {
        guard isOnWatch else { return }
        pendingAlerts.append(alert)
        publishToWatch()
    }

    var workout: FunctionalWorkout { session.workout }
    var isFinished: Bool { session.isFinished }

    // MARK: Station details

    /// The current station is a run outside (GPS distance and pace).
    var isOutdoorRun: Bool {
        guard let station = session.station, session.phase == .work, !session.isWaitingForInterval else { return false }
        return station.kind == .run && !station.treadmill
    }

    /// The pace to hold on a run station (nil = by feel, or no training paces yet for a zone).
    func paceRange(for station: FunctionalStation) -> PaceRange? {
        guard station.kind == .run, let pace = station.pace else { return nil }
        if case .zone = pace, paceZones == nil { return nil }
        return pace.range(zones: paceZones ?? PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 1500)))
    }

    /// "4:00/km", "4:05–4:15/km (Intervals pace)", or nil.
    func paceText(for station: FunctionalStation) -> String? {
        guard let range = paceRange(for: station) else { return nil }
        let format = DisplayFormat(units: units)
        let text = range.fastest == range.slowest ? format.pace(range.fastest) : format.paceRange(range)
        if case .zone(let zone) = station.pace { return "\(text) · \(zone.displayName) pace" }
        return text
    }

    /// Treadmill speed for a run station's pace: "15.0 km/h" (the middle of a range).
    func treadmillSpeed(for station: FunctionalStation) -> String? {
        guard station.treadmill, let range = paceRange(for: station) else { return nil }
        let middle = Pace(secondsPerKm: (range.fastest.secondsPerKm + range.slowest.secondsPerKm) / 2)
        if units == .imperial {
            return String(format: "%.1f mph", middle.kilometresPerHour / 1.609344)
        }
        return String(format: "%.1f km/h", middle.kilometresPerHour)
    }

    /// Where the current pace is against the target (outdoor run stations with a pace).
    var pacePosition: PaceRange.Position? {
        guard isOutdoorRun, let station = session.station, let range = paceRange(for: station), let currentPace else { return nil }
        return range.position(of: currentPace, toleranceSecondsPerKm: paceTolerance)
    }

    func currentHeartRate(at date: Date) -> Double? {
        guard let heartRateAt, date.timeIntervalSince(heartRateAt) < 30 else { return nil }
        return heartRate
    }

    // MARK: Controls

    func next() {
        let meters = isOutdoorRun ? stationMeters : nil
        session.next(at: Date(), meters: meters)
        stationChanged()
        haptic(.success)
    }

    func undo() {
        session.undo()
        stationChanged()
        haptic(.warning)
    }

    func finish() {
        session.finish(at: Date(), meters: isOutdoorRun ? stationMeters : nil)
        stationChanged()
    }

    /// Saves it (counts towards training load, goes to Health and Strava like a gym session).
    func save(effort: Double, title: String) {
        guard savedLog == nil else { return }
        let record = self.record ?? FunctionalRecord(session: session)
        let end = Date()
        let log = StrengthLogModel(plannedSessionId: nil, startedAt: session.startedAt)
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        log.title = trimmed.isEmpty ? workout.name : trimmed
        log.isRecorded = true
        log.templateId = templateId
        log.functionalData = StoredJSON.encode(record)
        let duration = min((endedAt ?? end).timeIntervalSince(session.startedAt), 4 * 3600)
        log.durationSeconds = duration
        log.activeSeconds = record.splits.filter { $0.kind != .rest }.reduce(0) { $0 + $1.seconds }
        log.effort = effort
        log.load = SessionLoad.srpe(durationSeconds: duration, effort: effort)
        log.isFinished = true
        log.finishedAt = session.startedAt.addingTimeInterval(duration)
        log.touch(now: end)
        context.insert(log)
        if let templateId,
           let template = try? context.fetch(FetchDescriptor<FunctionalTemplateModel>(predicate: #Predicate { $0.id == templateId })).first {
            template.lastUsedAt = end
            template.touch(now: end)
        }
        try? context.save()
        SyncService.shared.requestSync()
        ActivityExportService.strengthFinished(log, units: units, in: context)
        savedLog = log
    }

    /// When the last station ended (the summary's total time).
    private(set) var endedAt: Date?

    var totalSeconds: Double { (endedAt ?? now).timeIntervalSince(session.startedAt) }

    /// Leaves the session: clocks, GPS and heart rate stop.
    func stop() {
        timer?.invalidate()
        timer = nil
        watchTimer?.invalidate()
        watchTimer = nil
        if isOnWatch {
            WatchMirrorService.shared.end(saved: savedLog != nil)
            isOnWatch = false
        }
        gps?.stop()
        gps = nil
        HeartRateMonitor.shared.onHeartRate = nil
        HeartRateMonitor.shared.disconnect()
        if let healthQuery { healthStore.stop(healthQuery) }
        healthQuery = nil
    }

    // MARK: Clock

    private func tick() {
        now = Date()
        guard !session.isFinished else { return }
        let before = stationKey
        let meters = isOutdoorRun ? stationMeters : nil
        if session.tick(at: now, meters: meters) {
            if stationKey != before {
                stationChanged()
                haptic(.success)
            }
        }
        countdownCue()
        targetCue()
        paceCue()
    }

    private var stationKey: String {
        "\(session.round)-\(session.stationIndex)-\(session.phase == .work ? "w" : "r")-\(session.isWaitingForInterval)-\(session.isFinished)-\(session.splits.count)"
    }

    private func stationChanged() {
        stationMeters = 0
        trail = []
        currentPace = nil
        lastSample = nil
        lastPaceCueAt = nil
        if session.isFinished {
            if record == nil {
                record = FunctionalRecord(session: session)
                endedAt = endedAt ?? Date()
                alertWatch(.complete)
                voice.speak("Workout done. \(Units.formatMinutesSeconds(totalSeconds))")
                haptic(.success)
            }
            return
        }
        record = nil
        endedAt = nil
        announceStation()
        alertWatch(.newStep)
    }

    // MARK: Cues

    private func announceStation() {
        let key = stationKey
        guard key != announcedStationKey, let station = session.station else { return }
        announcedStationKey = key
        if session.isWaitingForInterval { return }
        if session.phase == .rest {
            voice.speak("Rest. Next, \(spoken(session.nextStation ?? station))")
            return
        }
        var text = spoken(station)
        if let speed = treadmillSpeed(for: station) {
            text += ", treadmill \(speed.replacingOccurrences(of: "km/h", with: "kilometres an hour"))"
        } else if let range = paceRange(for: station) {
            text += " at \(Units.formatPace(range.fastest, units: units)) pace"
        }
        voice.speak(text)
    }

    private func spoken(_ station: FunctionalStation) -> String {
        var text = "\(station.name), \(station.target.text.replacingOccurrences(of: " m", with: " metres").replacingOccurrences(of: " cal", with: " calories"))"
        if let kg = station.weightKg, kg > 0 { text += ", \(DisplayFormat(units: units).weight(kg))" }
        return text
    }

    /// "3, 2, 1" buzzes as a timed window ends.
    @ObservationIgnored private var lastCountdownSecond = -1
    private func countdownCue() {
        guard let remaining = session.remaining(at: now) else { return }
        let whole = Int(remaining.rounded(.up))
        guard whole != lastCountdownSecond else { return }
        lastCountdownSecond = whole
        if (1...3).contains(whole) { haptic(.warning) }
    }

    /// Distance runs: say when the distance is done (they tap Next to move on).
    private func targetCue() {
        guard isOutdoorRun, case .meters(let target) = session.station?.target, stationMeters >= target else { return }
        guard targetReachedKey != stationKey else { return }
        targetReachedKey = stationKey
        voice.speak("\(session.station?.target.text.replacingOccurrences(of: " m", with: " metres") ?? "") done. Tap next.")
        haptic(.success)
        alertWatch(.split)
    }

    /// Speed up / ease off on a run station with a pace, at most every 30 seconds.
    private func paceCue() {
        guard paceCuesEnabled, isOutdoorRun, let station = session.station, let range = paceRange(for: station),
              session.phaseElapsed(at: now) > 20, let position = pacePosition else { return }
        if let last = lastPaceCueAt, now.timeIntervalSince(last) < 30 { return }
        switch position {
        case .onTarget: return
        case .tooSlow:
            voice.speak("Speed up. Target \(Units.formatPace(range.slowest, units: units))")
            alertWatch(.speedUp)
        case .tooFast:
            voice.speak("Ease off. Target \(Units.formatPace(range.fastest, units: units))")
            alertWatch(.easeOff)
        }
        lastPaceCueAt = now
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    // MARK: GPS

    private func startGPS() {
        let gps = GPSLocationSource()
        gps.requestPermission()
        gps.onSample = { [weak self] sample in self?.receive(sample) }
        gps.start()
        self.gps = gps
    }

    private func receive(_ sample: LocationSample) {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 30 else { return }
        hasGPSFix = true
        guard isOutdoorRun else { lastSample = sample; return }
        defer { lastSample = sample }
        guard let last = lastSample else {
            trail = [(sample.timestamp, stationMeters)]
            return
        }
        let step = Geo.distance(last.latitude, last.longitude, sample.latitude, sample.longitude)
        let seconds = sample.timestamp.timeIntervalSince(last.timestamp)
        // Ignore jumps faster than a sprint.
        guard seconds > 0, step / seconds < 10 else { return }
        stationMeters += step
        trail.append((sample.timestamp, stationMeters))
        trail.removeAll { sample.timestamp.timeIntervalSince($0.at) > 20 }
        if let first = trail.first, sample.timestamp.timeIntervalSince(first.at) >= 8, stationMeters - first.meters > 5 {
            let pace = sample.timestamp.timeIntervalSince(first.at) / (stationMeters - first.meters) * 1000
            currentPace = pace < 1200 ? Pace(secondsPerKm: pace) : nil
        }
    }

    // MARK: Heart rate

    private func startHeartRate() {
        let monitor = HeartRateMonitor.shared
        monitor.onHeartRate = { [weak self] bpm, _ in
            MainActor.assumeIsolated { self?.receiveHeartRate(bpm, strap: true, live: true) }
        }
        monitor.connectToSaved()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let predicate = HKQuery.predicateForSamples(withStart: session.startedAt.addingTimeInterval(-300), end: nil, options: [])
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
            guard let latest = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let bpm = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            let at = latest.endDate
            Task { @MainActor in
                guard Date().timeIntervalSince(at) < 180 else { return }
                self?.receiveHeartRate(bpm, strap: false, live: false)
            }
        }
        let query = HKAnchoredObjectQuery(type: HKQuantityType(.heartRate), predicate: predicate, anchor: nil,
                                          limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        healthStore.execute(query)
        healthQuery = query
    }

    /// A chest strap wins over the watch, and both over readings saved to Health.
    private func receiveHeartRate(_ bpm: Double, strap: Bool, live: Bool) {
        guard bpm > 30, bpm < 250 else { return }
        let date = Date()
        if !strap, let lastStrapAt, date.timeIntervalSince(lastStrapAt) < 10 { return }
        if !live, let lastWatchHeartRateAt, date.timeIntervalSince(lastWatchHeartRateAt) < 15 { return }
        if strap { lastStrapAt = date }
        heartRate = bpm
        heartRateAt = date
        maxHeartRate = max(maxHeartRate ?? 0, bpm)
    }
}
