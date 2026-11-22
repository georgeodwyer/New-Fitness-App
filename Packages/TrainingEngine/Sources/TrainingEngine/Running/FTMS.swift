import Foundation

/// The Bluetooth Fitness Machine Service (FTMS, 0x1826) for treadmills: reading the belt's
/// speed, distance and incline (Treadmill Data, 0x2ACD) and sending commands through the
/// Fitness Machine Control Point (0x2AD9). Byte layouts follow the Bluetooth FTMS 1.0 spec.
public enum FTMS {
    /// One Treadmill Data notification. Fields the treadmill doesn't send are nil.
    public struct Reading: Equatable, Sendable {
        public var speedKmh: Double?
        public var totalMeters: Double?
        public var inclinePercent: Double?
        public var heartRate: Int?
        public var elapsedSeconds: Double?

        public init(speedKmh: Double? = nil, totalMeters: Double? = nil, inclinePercent: Double? = nil,
                    heartRate: Int? = nil, elapsedSeconds: Double? = nil) {
            self.speedKmh = speedKmh
            self.totalMeters = totalMeters
            self.inclinePercent = inclinePercent
            self.heartRate = heartRate
            self.elapsedSeconds = elapsedSeconds
        }
    }

    /// The speeds the treadmill accepts (Supported Speed Range, 0x2AD4), km/h.
    public struct SpeedRange: Equatable, Sendable {
        public var minimum: Double
        public var maximum: Double
        public var step: Double

        public init(minimum: Double, maximum: Double, step: Double) {
            self.minimum = minimum
            self.maximum = maximum
            self.step = step
        }
    }

    // MARK: Reading

    /// Parses Treadmill Data. nil if it's too short to be one.
    public static func reading(_ bytes: [UInt8]) -> Reading? {
        guard bytes.count >= 2 else { return nil }
        let flags = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        var cursor = 2
        var reading = Reading()
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }
        func u8() -> Int? {
            guard cursor + 1 <= bytes.count else { return nil }
            defer { cursor += 1 }
            return Int(bytes[cursor])
        }
        func u16() -> Int? {
            guard cursor + 2 <= bytes.count else { return nil }
            defer { cursor += 2 }
            return Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8
        }
        func s16() -> Int? { u16().map { $0 >= 0x8000 ? $0 - 0x10000 : $0 } }
        func u24() -> Int? {
            guard cursor + 3 <= bytes.count else { return nil }
            defer { cursor += 3 }
            return Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8 | Int(bytes[cursor + 2]) << 16
        }
        // Bit 0 is "more data": the instantaneous speed is present when it's 0.
        if !has(0) { reading.speedKmh = u16().map { Double($0) / 100 } }
        if has(1) { _ = u16() }                                          // average speed
        if has(2) { reading.totalMeters = u24().map(Double.init) }       // total distance
        if has(3) {                                                       // inclination + ramp angle
            reading.inclinePercent = s16().map { Double($0) / 10 }
            _ = s16()
        }
        if has(4) { _ = u16(); _ = u16() }                               // elevation gain (+, −)
        if has(5) { _ = u8() }                                           // instantaneous pace
        if has(6) { _ = u8() }                                           // average pace
        if has(7) { _ = u16(); _ = u16(); _ = u8() }                     // energy: total, per hour, per minute
        if has(8) { reading.heartRate = u8().flatMap { $0 > 0 ? $0 : nil } }
        if has(9) { _ = u8() }                                           // metabolic equivalent
        if has(10) { reading.elapsedSeconds = u16().map(Double.init) }   // elapsed time
        return reading
    }

    /// Parses Supported Speed Range (three uint16 in 0.01 km/h).
    public static func speedRange(_ bytes: [UInt8]) -> SpeedRange? {
        guard bytes.count >= 6 else { return nil }
        func u16(_ at: Int) -> Double { Double(Int(bytes[at]) | Int(bytes[at + 1]) << 8) / 100 }
        let range = SpeedRange(minimum: u16(0), maximum: u16(2), step: max(u16(4), 0.1))
        return range.maximum > range.minimum ? range : nil
    }

    // MARK: Commands

    public enum Opcode: UInt8, Sendable {
        case requestControl = 0x00, reset = 0x01, setTargetSpeed = 0x02, setTargetInclination = 0x03
        case startOrResume = 0x07, stopOrPause = 0x08
        case response = 0x80
    }

    public static let requestControl: [UInt8] = [Opcode.requestControl.rawValue]
    public static let startOrResume: [UInt8] = [Opcode.startOrResume.rawValue]
    public static let pause: [UInt8] = [Opcode.stopOrPause.rawValue, 0x02]
    public static let stop: [UInt8] = [Opcode.stopOrPause.rawValue, 0x01]

    public static func setSpeed(kilometresPerHour kmh: Double) -> [UInt8] {
        let value = UInt16(clamping: Int((max(kmh, 0) * 100).rounded()))
        return [Opcode.setTargetSpeed.rawValue, UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    public static func setIncline(percent: Double) -> [UInt8] {
        let value = Int16(clamping: Int((percent * 10).rounded()))
        let raw = UInt16(bitPattern: value)
        return [Opcode.setTargetInclination.rawValue, UInt8(raw & 0xFF), UInt8(raw >> 8)]
    }

    /// A Control Point response: which command it answers and whether it worked.
    public static func response(_ bytes: [UInt8]) -> (opcode: UInt8, succeeded: Bool)? {
        guard bytes.count >= 3, bytes[0] == Opcode.response.rawValue else { return nil }
        return (bytes[1], bytes[2] == 0x01)
    }

    // MARK: Speeds for a run

    /// The belt speed for a pace target: the middle of the range, never faster than its fast
    /// end, in the treadmill's steps and within what it supports.
    public static func speed(for target: PaceRange, supported: SpeedRange?) -> Double {
        let middle = Pace(secondsPerKm: (target.fastest.secondsPerKm + target.slowest.secondsPerKm) / 2).kilometresPerHour
        let fastest = target.fastest.kilometresPerHour
        var kmh = min(middle, fastest)
        if let supported {
            kmh = (kmh / supported.step + 1e-6).rounded(.down) * supported.step
            kmh = min(max(kmh, supported.minimum), supported.maximum)
        } else {
            kmh = (kmh * 10 + 1e-6).rounded(.down) / 10
        }
        return (kmh * 100).rounded() / 100
    }
}
