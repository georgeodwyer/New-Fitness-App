import Foundation

/// One heart-rate reading during a run, at `elapsed` seconds of active running.
public struct HeartRateSample: Codable, Equatable, Sendable {
    public var elapsed: Double
    public var bpm: Double

    public init(elapsed: Double, bpm: Double) {
        self.elapsed = elapsed
        self.bpm = bpm
    }
}

/// A decoded Bluetooth "Heart Rate Measurement" (characteristic 0x2A37, service 0x180D).
///
/// Byte 0 is a flags field:
/// - bit 0: heart rate is UInt16 (else UInt8)
/// - bits 1–2: sensor contact (bit 2 = supported, bit 1 = detected)
/// - bit 3: energy expended (UInt16, kJ) is present
/// - bit 4: RR intervals (UInt16 each, 1/1024 s) follow
public struct HeartRateMeasurement: Equatable, Sendable {
    public var bpm: Int
    /// nil if the strap doesn't report skin contact.
    public var sensorContact: Bool?
    public var energyExpendedKJ: Int?
    /// Beat-to-beat intervals in seconds.
    public var rrIntervals: [Double]

    public init(bpm: Int, sensorContact: Bool? = nil, energyExpendedKJ: Int? = nil, rrIntervals: [Double] = []) {
        self.bpm = bpm
        self.sensorContact = sensorContact
        self.energyExpendedKJ = energyExpendedKJ
        self.rrIntervals = rrIntervals
    }

    /// Parses the raw characteristic value. Returns nil for malformed data.
    public static func parse(_ data: Data) -> HeartRateMeasurement? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        var index = 1

        func uint16() -> Int? {
            guard index + 1 < bytes.count else { return nil }
            defer { index += 2 }
            return Int(bytes[index]) | Int(bytes[index + 1]) << 8
        }

        let bpm: Int
        if flags & 0x01 != 0 {
            guard let value = uint16() else { return nil }
            bpm = value
        } else {
            guard index < bytes.count else { return nil }
            bpm = Int(bytes[index])
            index += 1
        }

        let contact: Bool? = flags & 0x04 != 0 ? (flags & 0x02 != 0) : nil

        var energy: Int?
        if flags & 0x08 != 0 {
            guard let value = uint16() else { return nil }
            energy = value
        }

        var rr: [Double] = []
        if flags & 0x10 != 0 {
            while let value = uint16() { rr.append(Double(value) / 1024) }
        }
        return HeartRateMeasurement(bpm: bpm, sensorContact: contact, energyExpendedKJ: energy, rrIntervals: rr)
    }

    /// A reading worth using: plausible, and not flagged as "strap not touching skin".
    public var isUsable: Bool { sensorContact != false && bpm > 30 && bpm < 250 }
}

/// Compares this morning's resting heart rate with the runner's usual.
///
/// A resting heart rate well above normal is a common early sign of fatigue, illness or
/// poor sleep, so it's used as one recovery signal alongside the check-in.
public struct RestingHeartRateSignal: Equatable, Sendable {
    public var today: Double
    /// Median of the previous readings.
    public var baseline: Double
    public var difference: Double { today - baseline }
    /// At least `RestingHeartRateSignal.elevatedThreshold` bpm above usual.
    public var isElevated: Bool { difference >= Self.elevatedThreshold }

    public static var elevatedThreshold: Double { BalanceRules.current.recovery.restingHeartRateElevatedBpm }
    /// Readings needed before a baseline means anything.
    public static var minimumHistory: Int { BalanceRules.current.recovery.restingHeartRateMinimumReadings }

    public init(today: Double, baseline: Double) {
        self.today = today
        self.baseline = baseline
    }

    /// `history` is the previous days' readings (most recent ~4 weeks), not including today.
    public static func assess(today: Double, history: [Double]) -> RestingHeartRateSignal? {
        let usable = history.filter { $0 > 25 && $0 < 150 }
        guard usable.count >= minimumHistory, today > 25, today < 150 else { return nil }
        let sorted = usable.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return RestingHeartRateSignal(today: today, baseline: median)
    }

    /// "52 bpm · 6 above your usual"
    public var description: String {
        let delta = Int(difference.rounded())
        let comparison: String
        if delta == 0 { comparison = "same as your usual" }
        else if delta > 0 { comparison = "\(delta) above your usual" }
        else { comparison = "\(-delta) below your usual" }
        return "\(Int(today.rounded())) bpm · \(comparison)"
    }
}
