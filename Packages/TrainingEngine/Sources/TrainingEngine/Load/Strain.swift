import Foundation

// Daily exertion (0–100), heart-rate zones, recovery (0–100), a daily strain target and legs
// load. Exertion is a log scale: each point is harder to earn than the last (an easy hour
// ≈ 45, a hard hour ≈ 60, a very big day 90+).
//
// Under the hood everything is "load": minutes weighted by intensity. With heart rate, each
// minute counts its zone number (zone 1 = 1 … zone 5 = 5, Edwards' TRIMP). Without it, a
// session counts minutes × effort ÷ 2, which lands in the same place (an easy hour ≈ 120,
// a hard hour ≈ 240). Steps outside workouts add everyday activity.

// MARK: - Heart-rate zones

/// The runner's own zone settings (all optional: nil = worked out automatically).
public struct HeartRateZoneSettings: Codable, Equatable, Sendable {
    /// Max heart rate they've set themselves.
    public var maxHeartRate: Double?
    /// Where zones 1–5 start, in bpm (five rising values), when they've set them.
    public var zoneStarts: [Double]?

    public init(maxHeartRate: Double? = nil, zoneStarts: [Double]? = nil) {
        self.maxHeartRate = maxHeartRate
        self.zoneStarts = zoneStarts
    }

    public var isCustom: Bool { maxHeartRate != nil || zoneStarts != nil }
}

public struct HeartRateZones: Equatable, Sendable {
    public enum MaxSource: String, Equatable, Sendable {
        /// 208 − 0.7 × age (Tanaka).
        case age
        /// Higher than the age estimate in their own recorded runs.
        case recorded
        /// Set by them in Settings.
        case custom
        /// No age or recordings yet.
        case typical
    }

    public var maxHeartRate: Double
    public var maxSource: MaxSource
    /// Where zones 1–5 start (bpm), rising.
    public var starts: [Double]
    /// The zones were set by hand.
    public var isCustom: Bool

    public init(maxHeartRate: Double, maxSource: MaxSource, starts: [Double], isCustom: Bool) {
        self.maxHeartRate = maxHeartRate
        self.maxSource = maxSource
        self.starts = starts
        self.isCustom = isCustom
    }

    /// Zone starts as a share of max: 50, 60, 70, 80, 90%.
    public static let startShares: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
    public static let names = ["Very light", "Easy", "Moderate", "Hard", "Max"]

    public static func ageEstimate(age: Int) -> Double { (208 - 0.7 * Double(age)).rounded() }

    /// The highest believable max from recorded runs: the second-highest run max of the last
    /// year (one optical-sensor spike can't move it), nil when there aren't two.
    public static func recordedMax(_ runMaxima: [Double]) -> Double? {
        let plausible = runMaxima.filter { $0 > 120 && $0 < 225 }.sorted(by: >)
        return plausible.count >= 2 ? plausible[1] : nil
    }

    public static func make(age: Int?, recordedMax: Double?, settings: HeartRateZoneSettings? = nil) -> HeartRateZones {
        let estimate = age.map(ageEstimate)
        var max: Double
        var source: MaxSource
        if let custom = settings?.maxHeartRate, custom > 100 {
            max = custom; source = .custom
        } else if let estimate {
            max = estimate; source = .age
            if let recordedMax, recordedMax > estimate { max = recordedMax; source = .recorded }
        } else if let recordedMax {
            max = recordedMax; source = .recorded
        } else {
            max = 190; source = .typical
        }
        if let starts = settings?.zoneStarts, starts.count == 5, zip(starts, starts.dropFirst()).allSatisfy({ $0 < $1 }) {
            return HeartRateZones(maxHeartRate: Swift.max(max, starts[4] + 1), maxSource: source, starts: starts, isCustom: true)
        }
        return HeartRateZones(maxHeartRate: max, maxSource: source, starts: startShares.map { ($0 * max).rounded() }, isCustom: false)
    }

    /// 0 below zone 1, else 1–5.
    public func zone(for bpm: Double) -> Int {
        starts.lastIndex { bpm >= $0 }.map { $0 + 1 } ?? 0
    }

    /// "142–155" for a zone 1–5 (zone 5 runs to max).
    public func range(of zone: Int) -> ClosedRange<Double> {
        let index = Swift.min(Swift.max(zone, 1), 5) - 1
        let upper = index < 4 ? starts[index + 1] - 1 : maxHeartRate
        return starts[index]...Swift.max(starts[index], upper)
    }
}

// MARK: - Strain

public enum Strain {
    public static let maximum = 100.0
    /// Load at which exertion reaches 100 (about four hours of hard racing).
    static let fullLoad = 1000.0
    /// Shapes the curve: lower makes small days score higher.
    static let softness = 30.0

    /// 0–100 from a day's load.
    public static func strain(load: Double) -> Double {
        guard load > 0 else { return 0 }
        return min(maximum, maximum * log(1 + load / softness) / log(1 + fullLoad / softness))
    }

    /// The load that gives a strain (inverse of `strain(load:)`).
    public static func load(forStrain strain: Double) -> Double {
        let clamped = min(max(strain, 0), maximum)
        return softness * (exp(clamped / maximum * log(1 + fullLoad / softness)) - 1)
    }

    /// Weight per minute in each zone (0 = below zone 1).
    static let zoneWeights: [Double] = [0.5, 1, 2, 3, 4, 5]

    /// From heart-rate samples: minutes in each zone × its weight. Gaps over 15 s count as 15 s.
    public static func load(samples: [HeartRateSample], zones: HeartRateZones) -> Double {
        let sorted = samples.filter { $0.bpm > 30 && $0.bpm < 250 }.sorted { $0.elapsed < $1.elapsed }
        guard sorted.count >= 2 else { return 0 }
        var total = 0.0
        for (sample, next) in zip(sorted, sorted.dropFirst()) {
            let seconds = min(max(next.elapsed - sample.elapsed, 0), 15)
            total += seconds / 60 * zoneWeights[zones.zone(for: sample.bpm)]
        }
        return total
    }

    /// Minutes in each zone (index 0 = below zone 1), for the run summary.
    public static func minutesInZones(samples: [HeartRateSample], zones: HeartRateZones) -> [Double] {
        let sorted = samples.filter { $0.bpm > 30 && $0.bpm < 250 }.sorted { $0.elapsed < $1.elapsed }
        var minutes = Array(repeating: 0.0, count: 6)
        for (sample, next) in zip(sorted, sorted.dropFirst()) {
            minutes[zones.zone(for: sample.bpm)] += min(max(next.elapsed - sample.elapsed, 0), 15) / 60
        }
        return minutes
    }

    /// From an average heart rate over the whole session.
    public static func load(averageHeartRate: Double, durationSeconds: Double, zones: HeartRateZones) -> Double {
        durationSeconds / 60 * zoneWeights[zones.zone(for: averageHeartRate)]
    }

    /// Without heart rate: minutes × effort (1–10) ÷ 2.
    public static func load(durationSeconds: Double, effort: Double) -> Double {
        SessionLoad.srpe(durationSeconds: durationSeconds, effort: effort) / 2
    }

    /// A gym session. Heart rate reads low for lifting (short sets, long rests, the effort is in the
    /// muscles more than the heart), so with heart rate the load is half heart rate and half
    /// minutes × effort; without it, minutes × effort alone.
    /// - Parameters:
    ///   - zoneSeconds: seconds in each zone recorded during the session (index 0 = below zone 1).
    ///     Used when they cover at least 30% of the session, scaled up to the whole of it.
    ///   - averageHeartRate: the session's average (e.g. from the watch's workout in Health), when
    ///     there are no zone seconds.
    public static func gymLoad(durationSeconds: Double, effort: Double, zoneSeconds: [Double]?, averageHeartRate: Double?,
                               zones: HeartRateZones) -> (load: Double, usedHeartRate: Bool) {
        let byEffort = load(durationSeconds: durationSeconds, effort: effort)
        var byHeartRate: Double?
        if let zoneSeconds, zoneSeconds.count == zoneWeights.count {
            let covered = zoneSeconds.reduce(0, +)
            if covered > 0, covered >= 0.3 * durationSeconds {
                let weighted = zip(zoneSeconds, zoneWeights).reduce(0) { $0 + $1.0 / 60 * $1.1 }
                byHeartRate = weighted * max(1, durationSeconds / covered)
            }
        }
        if byHeartRate == nil, let averageHeartRate, averageHeartRate > 0 {
            byHeartRate = load(averageHeartRate: averageHeartRate, durationSeconds: durationSeconds, zones: zones)
        }
        guard let byHeartRate else { return (byEffort, false) }
        return ((byHeartRate + byEffort) / 2, true)
    }

    /// Everyday activity: 3 per 1,000 steps (10,000 steps ≈ strain 4).
    public static func load(steps: Double) -> Double { max(0, steps) / 1000 * 3 }
}

/// One thing that added strain on a day.
public struct StrainActivity: Equatable, Sendable, Identifiable {
    public enum Source: String, Equatable, Sendable { case run, lift, other, steps }

    public var id: String
    public var date: Date
    public var source: Source
    public var name: String
    public var load: Double
    /// Share of the load that lands on the legs (runs 1, leg days most, upper body none).
    public var legsShare: Double
    /// Heart rate was used (rather than minutes × effort).
    public var usedHeartRate: Bool
    /// Steps taken during it (so they aren't counted again as everyday activity).
    public var steps: Double

    public init(id: String, date: Date, source: Source, name: String, load: Double, legsShare: Double, usedHeartRate: Bool = false,
                steps: Double = 0) {
        self.id = id
        self.date = date
        self.source = source
        self.name = name
        self.load = load
        self.legsShare = min(max(legsShare, 0), 1)
        self.usedHeartRate = usedHeartRate
        self.steps = max(0, steps)
    }

    /// Steps in a run or walk of this distance (about 1.1 m a step running, 0.75 m walking).
    public static func steps(meters: Double, running: Bool) -> Double { meters / (running ? 1.1 : 0.75) }

    public var strain: Double { Strain.strain(load: load) }
    public var legsLoad: Double { load * legsShare }

    /// Legs share for other activities by kind.
    public static func legsShare(for kind: ExternalWorkout.Kind) -> Double {
        switch kind {
        case .run: return 1
        case .cycling: return 0.6
        case .walking: return 0.5
        case .strength: return 0.4
        case .other: return 0.3
        }
    }
}

public struct DayStrain: Equatable, Sendable, Identifiable {
    public var date: Date
    public var activities: [StrainActivity]
    public var load: Double { activities.reduce(0) { $0 + $1.load } }
    public var strain: Double { Strain.strain(load: load) }
    public var id: Date { date }
}

// MARK: - Recovery

/// 0–100 from HRV and resting heart rate against their usual, sleep against their need, and
/// their score (morning check-in). Each reading is first measured against usual ("vs usual":
/// 50 = a normal day, 0 = far worse, 100 = far better), then shown on a friendlier scale where
/// a normal day is about 72, better than usual about 87 and far better 90+. The plan and the
/// exertion target use the vs-usual figure, so the display scale doesn't change any decisions.
public struct RecoveryScore: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        public var name: String
        /// This reading as shown, 0–100 (a normal day ≈ 72).
        public var score: Double
        /// This reading against usual, 0–100 (a normal day = 50).
        public var vsUsual: Double
        /// The reading, e.g. "61 ms · 4% below your usual".
        public var detail: String
        /// How the score is worked out, in a sentence.
        public var rule: String = ""
        /// Its share of today's recovery (weights rescaled to the readings available).
        public var share: Double = 0
        /// Points it adds to the total.
        public var points: Double { score * share }
    }

    public enum Band: String, Equatable, Sendable {
        case low, fair, good, great
        public var title: String {
            switch self {
            case .low: return "Low"
            case .fair: return "Fair"
            case .good: return "Good"
            case .great: return "Great"
            }
        }
    }

    /// How recovery moves today's exertion target.
    public enum TargetEffect: Equatable, Sendable { case lower, normal, higher }

    /// As shown, 0–100.
    public var score: Double
    public var parts: [Part]
    /// The readings against usual, 0–100 (50 = normal): what decisions use.
    public var vsUsual: Double

    public init(score: Double, parts: [Part], vsUsual: Double? = nil) {
        self.score = score
        self.parts = parts
        self.vsUsual = vsUsual ?? Self.vsUsual(fromShown: score)
    }

    public var band: Band { score < 50 ? .low : score < 70 ? .fair : score < 85 ? .good : .great }

    /// Clearly below usual eases the target; clearly above allows a bit more.
    public var targetEffect: TargetEffect {
        let multiplier = volumeMultiplier
        return multiplier < 1 ? .lower : multiplier > 1 ? .higher : .normal
    }

    /// How much of the planned training suits today's recovery (the shown score):
    /// 85+ → 105%, 67–84 → as planned, below 67 → 0.9% less per point, down to 60%.
    /// e.g. 50 → 85% (15% less). Used for the exertion target and lighter sessions.
    public var volumeMultiplier: Double { Self.volumeMultiplier(score: score) }

    public static func volumeMultiplier(score: Double) -> Double {
        if score >= 85 { return 1.05 }
        if score >= 67 { return 1 }
        return max(0.6, 1 - (67 - score) * 0.009)
    }

    /// "15% less", "5% more" or nil when as planned.
    public var volumeChangeText: String? {
        let percent = Int(((volumeMultiplier - 1) * 100).rounded())
        if percent == 0 { return nil }
        return percent < 0 ? "\(-percent)% less" : "\(percent)% more"
    }

    /// With a watch: their check-in 25%; the watch readings share the other 75% in their usual
    /// proportions (HRV 37.5%, resting/sleeping heart rate about 21%, sleep about 17%), so a day
    /// without a check-in scores just as before.
    static let weights = (hrv: 0.45 * 5 / 6, restingHeartRate: 0.25 * 5 / 6, sleep: 0.2 * 5 / 6, checkIn: 0.25)

    /// The display scale: vs usual → shown. Far worse 20, worse 50, normal 72, better 87, far better 98.
    static let scale: [(vsUsual: Double, shown: Double)] = [(0, 20), (25, 50), (50, 72), (75, 87), (100, 98)]

    public static func shown(vsUsual: Double) -> Double {
        let value = min(max(vsUsual, 0), 100)
        for (low, high) in zip(scale, scale.dropFirst()) where value <= high.vsUsual {
            let t = (value - low.vsUsual) / (high.vsUsual - low.vsUsual)
            return low.shown + t * (high.shown - low.shown)
        }
        return scale.last?.shown ?? value
    }

    static func vsUsual(fromShown shown: Double) -> Double {
        let value = min(max(shown, scale.first?.shown ?? 0), scale.last?.shown ?? 100)
        for (low, high) in zip(scale, scale.dropFirst()) where value <= high.shown {
            let t = (value - low.shown) / (high.shown - low.shown)
            return low.vsUsual + t * (high.vsUsual - low.vsUsual)
        }
        return 100
    }

    /// Without a watch (no HRV or resting heart rate), recovery comes from the check-in:
    /// sleep 30%, energy 30%, legs 25%, upper body 15% (soreness 40% on older check-ins with
    /// one soreness answer). With sleep from Apple Health, it shares the sleep 30% with the
    /// rating. Each rating: 3 shows as 72 (a normal day), 5 about 98, 1 about 20. The worst
    /// answer on anything (very sore legs, no energy…) caps the score at 55, two at 45, so a
    /// bad day always shows.
    static let checkInWeights = (sleep: 0.30, energy: 0.30, legs: 0.25, upperBody: 0.15)

    static func checkInOnly(_ checkIn: RecoveryCheckIn, sleepHours: Double?, usualSleepHours: Double?) -> RecoveryScore {
        var parts: [(Part, Double)] = []
        func add(_ name: String, rating: Int, best: Int, detail: String, weight: Double) {
            // Rating 1–5 (or 5–1 for soreness) → 0–100 against a normal day (3 = 50).
            let value = Double(best == 5 ? rating - 1 : 5 - rating) * 25
            parts.append((Part(name: name, score: shown(vsUsual: value), vsUsual: value, detail: detail,
                               rule: "Your check-in: 3 shows as 72, 5 about 98, 1 about 20."), weight))
        }
        let w = checkInWeights
        if let sleepHours, sleepHours > 0 {
            let need = sleepNeed(usual: usualSleepHours) ?? 7
            let value = min(max(50 + (sleepHours - need) * 25, 0), 100)
            parts.append((Part(name: "Sleep", score: shown(vsUsual: value), vsUsual: value,
                               detail: HealthMetric.sleep.format(sleepHours) + " asleep",
                               rule: "Hours asleep from Apple Health against your need: an hour less shows about 50."), w.sleep / 2))
            add("Sleep rating", rating: checkIn.sleep, best: 5, detail: "\(checkIn.sleep)/5", weight: w.sleep / 2)
        } else {
            add("Sleep rating", rating: checkIn.sleep, best: 5, detail: "\(checkIn.sleep)/5", weight: w.sleep)
        }
        add("Energy", rating: checkIn.energy, best: 5, detail: "\(checkIn.energy)/5", weight: w.energy)
        if let legs = checkIn.legSoreness {
            add("Legs", rating: legs, best: 1, detail: "\(6 - legs)/5", weight: w.legs)
            add("Upper body", rating: checkIn.soreness, best: 1, detail: "\(6 - checkIn.soreness)/5", weight: w.upperBody)
        } else {
            add("Soreness", rating: checkIn.soreness, best: 1, detail: "\(6 - checkIn.soreness)/5", weight: w.legs + w.upperBody)
        }
        let totalWeight = parts.reduce(0) { $0 + $1.1 }
        var score = parts.reduce(0) { $0 + $1.0.score * $1.1 } / totalWeight
        let worst = [checkIn.sleep == 1, checkIn.energy == 1, checkIn.legSoreness == 5, checkIn.soreness == 5].filter { $0 }.count
        let cap: Double? = worst >= 2 ? 45 : (worst == 1 ? 55 : nil)
        let scale = cap.map { min(1, $0 / max(score, 1)) } ?? 1
        if let cap { score = min(score, cap) }
        let shownScore = score.rounded()
        return RecoveryScore(score: shownScore, parts: parts.map { part, weight in
            var part = part
            part.share = weight / totalWeight
            // Capped: each part gives up the same share, so the breakdown still adds up.
            part.score *= scale
            return part
        }, vsUsual: vsUsual(fromShown: shownScore))
    }

    /// Sleep is scored against their need: their usual sleep, kept between 7 and 9 hours.
    public static func sleepNeed(usual: Double?) -> Double? {
        usual.map { min(max($0, 7), 9) }
    }

    /// - Parameter usualSleepHours: their typical night (median of recent nights); nil = not enough nights yet.
    public static func make(hrv: HRVSignal?, restingHeartRate: RestingHeartRateSignal?, sleepHours: Double?,
                            usualSleepHours: Double? = nil, checkIn: RecoveryCheckIn?) -> RecoveryScore? {
        var parts: [(Part, Double)] = []
        func add(_ name: String, vsUsual raw: Double, detail: String, rule: String, weight: Double) {
            let value = min(max(raw, 0), 100)
            parts.append((Part(name: name, score: shown(vsUsual: value), vsUsual: value, detail: detail, rule: rule), weight))
        }
        // No watch readings: the check-in is the score (see `checkInOnly`).
        if hrv == nil, restingHeartRate == nil, let checkIn {
            return checkInOnly(checkIn, sleepHours: sleepHours, usualSleepHours: usualSleepHours)
        }
        if let hrv {
            // Last night (or a recent average, when one is given); ±30% from usual spans the whole range.
            add("HRV", vsUsual: 50 + hrv.recentChange * 500 / 3, detail: hrv.recentDescription,
                rule: hrv.recentNights > 1
                    ? "Your last \(hrv.recentNights) nights against your usual: your usual shows as 72, 15% above about 87, 15% below about 50."
                    : "Last night against your usual: your usual shows as 72, 15% above about 87, 15% below about 50.",
                weight: weights.hrv)
        }
        if let restingHeartRate {
            add(restingHeartRate.isFromSleep ? "Sleeping HR" : "Resting HR", vsUsual: 50 - restingHeartRate.difference * 5,
                detail: restingHeartRate.description,
                rule: restingHeartRate.isFromSleep
                    ? "Your average heart rate while asleep last night against your usual: your usual shows as 72, 5 beats lower about 87, 5 beats higher about 50."
                    : "This morning against your usual: your usual shows as 72, 5 beats lower about 87, 5 beats higher about 50.",
                weight: weights.restingHeartRate)
        }
        if let sleepHours, sleepHours > 0 {
            if let need = sleepNeed(usual: usualSleepHours), let usual = usualSleepHours {
                let aim = usual == need ? "your usual \(HealthMetric.sleep.format(need))"
                    : "\(HealthMetric.sleep.format(need)) (your usual is \(HealthMetric.sleep.format(usual)))"
                add("Sleep", vsUsual: 50 + (sleepHours - need) * 25, detail: HealthMetric.sleep.format(sleepHours) + " asleep · aim " + aim,
                    rule: "Against your sleep need (your usual, kept between 7 and 9 hours): your need shows as 72, an hour more about 87, an hour less about 50.",
                    weight: weights.sleep)
            } else {
                add("Sleep", vsUsual: (sleepHours - 4) / 4 * 100, detail: HealthMetric.sleep.format(sleepHours) + " asleep",
                    rule: "Until Kinetix knows your usual sleep: 6 hours shows as 72, 7 hours about 87, 5 hours about 50.",
                    weight: weights.sleep)
            }
        }
        if let checkIn {
            add("Your score", vsUsual: checkIn.readiness * 100,
                detail: checkIn.legSoreness.map {
                    "Sleep \(checkIn.sleep)/5 · legs \($0)/5 · upper body \(checkIn.soreness)/5 · energy \(checkIn.energy)/5"
                } ?? "Sleep \(checkIn.sleep)/5 · soreness \(checkIn.soreness)/5 · energy \(checkIn.energy)/5",
                rule: "Your sleep, soreness and energy ratings: all 3s show as 72.", weight: weights.checkIn)
        }
        guard !parts.isEmpty else { return nil }
        let totalWeight = parts.reduce(0) { $0 + $1.1 }
        let shownTotal = parts.reduce(0) { $0 + $1.0.score * $1.1 } / totalWeight
        let vsUsualTotal = parts.reduce(0) { $0 + $1.0.vsUsual * $1.1 } / totalWeight
        return RecoveryScore(score: shownTotal.rounded(), parts: parts.map { part, weight in
            var part = part
            part.share = weight / totalWeight
            return part
        }, vsUsual: vsUsualTotal)
    }
}

// MARK: - Daily target

public struct StrainTarget: Equatable, Sendable {
    public var low: Double
    public var high: Double
    /// One sentence on why.
    public var reason: String

    public var middle: Double { (low + high) / 2 }

    public func contains(_ strain: Double) -> Bool { strain >= low && strain <= high }

    /// Today's target: the plan's sessions plus everyday activity, nudged by recovery
    /// (see `RecoveryScore.volumeMultiplier`). Without a plan, their usual day.
    /// - Parameters:
    ///   - plannedLoad: today's planned sessions as load (nil = no plan).
    ///   - everydayLoad: their typical non-workout activity (steps) as load.
    ///   - usualDailyLoad: their average daily load over the last four weeks.
    public static func make(plannedLoad: Double?, everydayLoad: Double, usualDailyLoad: Double,
                            recovery: RecoveryScore?) -> StrainTarget {
        var load = (plannedLoad ?? max(usualDailyLoad - everydayLoad, 0)) + everydayLoad
        var reason: String
        if let plannedLoad {
            reason = plannedLoad > 0 ? "Today's sessions plus your usual daily activity." : "A rest day: just your usual daily activity."
        } else {
            reason = "Your usual day over the last four weeks."
        }
        if let recovery, let change = recovery.volumeChangeText {
            load *= recovery.volumeMultiplier
            reason += recovery.volumeMultiplier > 1
                ? " Recovery is \(Int(recovery.score.rounded())), so there's room for \(change)."
                : " Recovery is \(Int(recovery.score.rounded())), so aim for \(change) today."
        }
        let middle = Strain.strain(load: load)
        return StrainTarget(low: max(0, middle - 7), high: min(Strain.maximum, middle + 7), reason: reason)
    }

    /// A planned session's expected load: minutes × planned effort ÷ 2.
    public static func plannedLoad(minutes: Double, effort: Double) -> Double {
        Strain.load(durationSeconds: minutes * 60, effort: effort)
    }
}

// MARK: - Legs

/// How tired the legs are: recent leg load (halving every 36 hours) against their usual.
public struct LegsLoad: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case fresh, ok, tired
        public var title: String {
            switch self {
            case .fresh: return "Fresh"
            case .ok: return "OK"
            case .tired: return "Tired"
            }
        }
        public var advice: String {
            switch self {
            case .fresh: return "Legs are fresh: a good day for a hard run or leg day."
            case .ok: return "Legs are carrying normal training fatigue."
            case .tired: return "Legs are more tired than usual: keep running easy and go light on legs."
            }
        }
    }

    public var current: Double
    /// Their usual (median over the last four weeks), nil without two weeks of history.
    public var usual: Double?
    public var status: Status

    static let halfLifeHours = 36.0

    public static func fatigue(at time: Date, activities: [StrainActivity]) -> Double {
        activities.reduce(0) { total, activity in
            let hours = time.timeIntervalSince(activity.date) / 3600
            guard hours >= 0 else { return total }
            return total + activity.legsLoad * pow(0.5, hours / halfLifeHours)
        }
    }

    /// How their legs feel overrides the numbers when it's worse: very sore (4–5) is tired,
    /// a bit sore (3) is at least OK.
    public func feeling(_ legSoreness: Int?) -> LegsLoad {
        guard let legSoreness else { return self }
        var result = self
        if legSoreness >= 4 { result.status = .tired } else if legSoreness == 3 && status == .fresh { result.status = .ok }
        return result
    }

    public static func make(activities: [StrainActivity], now: Date, calendar: Calendar) -> LegsLoad {
        let current = fatigue(at: now, activities: activities)
        let first = activities.map(\.date).min()
        var history: [Double] = []
        for daysAgo in 1...28 {
            guard let time = calendar.date(byAdding: .day, value: -daysAgo, to: now), let first, time >= first else { continue }
            history.append(fatigue(at: time, activities: activities.filter { $0.date <= time }))
        }
        if history.count >= 14 {
            let usual = HealthTrend.median(history)
            let ratio = usual > 0 ? current / usual : (current > 0 ? 2 : 0)
            let status: Status = ratio < 0.8 ? .fresh : ratio <= 1.3 ? .ok : .tired
            return LegsLoad(current: current, usual: usual, status: status)
        }
        // Not enough history: fixed levels (an easy hour's run ≈ 120).
        let status: Status = current < 80 ? .fresh : current < 220 ? .ok : .tired
        return LegsLoad(current: current, usual: nil, status: status)
    }
}

// MARK: - Report

/// Everything the strain card shows.
public struct StrainReport: Equatable, Sendable {
    public var today: DayStrain
    /// Last 30 days, oldest first (today last).
    public var days: [DayStrain]
    public var target: StrainTarget
    public var recovery: RecoveryScore?
    public var legs: LegsLoad
    /// The last 7 days' load against an average week of the last 28 (1.0 = usual), nil early on.
    public var weekVsUsual: Double?

    /// - Parameters:
    ///   - activities: sessions and other workouts (not steps).
    ///   - steps: daily step totals; workouts' share of steps is taken off (runs ≈ 1 step per 1.1 m).
    public static func make(activities: [StrainActivity], steps: [HealthDay], plannedLoadToday: Double?,
                            recovery: RecoveryScore?, legSoreness: Int? = nil, now: Date, calendar: Calendar) -> StrainReport {
        let today = calendar.startOfDay(for: now)
        func dayActivities(_ date: Date) -> [StrainActivity] {
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return [] }
            return activities.filter { $0.date >= date && $0.date < next }
        }
        func everyday(_ date: Date, workouts: [StrainActivity]) -> StrainActivity? {
            guard let total = steps.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.value, total > 0 else { return nil }
            // Steps taken during runs and walks are already in those sessions.
            let inWorkouts = workouts.reduce(0.0) { $0 + $1.steps }
            let outside = max(0, total - inWorkouts)
            return StrainActivity(id: "steps-\(date.timeIntervalSince1970)", date: date, source: .steps,
                                  name: "Everyday activity", load: Strain.load(steps: outside), legsShare: 0)
        }
        let days: [DayStrain] = (0..<30).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let workouts = dayActivities(date)
            return DayStrain(date: date, activities: workouts + [everyday(date, workouts: workouts)].compactMap { $0 })
        }
        let todayStrain = days.last ?? DayStrain(date: today, activities: [])

        // Everyday activity: median of the last two weeks' step load (before today), else 10,000 steps' worth.
        let stepLoads = days.dropLast().suffix(14).compactMap { day in day.activities.first { $0.source == .steps }?.load }
        let everydayLoad = stepLoads.count >= 3 ? HealthTrend.median(stepLoads) : Strain.load(steps: 7000)
        let past28 = days.dropLast().suffix(28)
        let usualDaily = past28.isEmpty ? 0 : past28.reduce(0) { $0 + $1.load } / Double(past28.count)
        let target = StrainTarget.make(plannedLoad: plannedLoadToday, everydayLoad: everydayLoad,
                                       usualDailyLoad: usualDaily, recovery: recovery)

        var weekVsUsual: Double?
        let firstDate = activities.map(\.date).min()
        if let firstDate, let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDate), to: today).day,
           span >= 13 {
            let last7 = days.suffix(7).reduce(0) { $0 + $1.load }
            let last28 = days.suffix(28).reduce(0) { $0 + $1.load } / 4
            if last28 > 0 { weekVsUsual = last7 / last28 }
        }

        return StrainReport(today: todayStrain, days: days, target: target, recovery: recovery,
                            legs: LegsLoad.make(activities: activities, now: now, calendar: calendar).feeling(legSoreness),
                            weekVsUsual: weekVsUsual)
    }
}
