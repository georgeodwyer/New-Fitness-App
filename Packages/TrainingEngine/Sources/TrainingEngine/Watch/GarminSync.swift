import Foundation

// What the iPhone and the Kinetix Garmin watch app (Connect IQ, in garmin/) send each other.
// Garmin's phone link carries plain dictionaries of strings and numbers, so the plan and
// results are kept small with short keys. Both sides ignore keys they don't know.
//
// Phone → watch, the plan:
//   ["t": "plan", "v": 1, "u": "km" | "mi", "tol": 10, "cue": 20, "cues": 1,
//    "s": [["id": uuid, "n": title, "d": detail, "day": epoch seconds, "src": "planned" | "template",
//           "st": [["k": "u" warm-up | "w" work | "r" recovery | "c" cool-down | "s" steady,
//                   "l": label, "m": metres (0 when timed), "sec": seconds (0 when by distance),
//                   "f": fastest s/km (0 = no target), "sl": slowest s/km, "g": 1 when the pace is a guide]]]]]
// Phone → watch: ["t": "ack", "rid": result id] once a result is saved.
// Watch → phone: ["t": "hello"] when the app opens (the phone replies with the plan), and
//   ["t": "result", "rid": unique id, "id": session id or "", "src": "planned" | "template" | "free",
//    "n": title, "start": epoch, "end": epoch, "dur": timer seconds, "dist": metres, "hr": avg, "hrx": max,
//    "seg": [["i": step index, "dur": s, "dist": m, "in": seconds on target, "ms": seconds measured, "hr": avg]],
//    "spl": [[seconds, avg hr]] per km or mile, "lap": [[seconds, metres, avg hr]] laps pressed after the plan ended]
public enum GarminSync {
    /// The Kinetix watch app's id in Garmin's Connect IQ store (also in garmin/manifest.xml).
    public static let watchAppId = "80ce02b8-9c7d-47bf-9ddb-aedbbd400dea"
    public static let version = 1

    // MARK: Plan → watch

    public static func planMessage(_ plan: WatchPlan) -> [String: Any] {
        let sessions: [[String: Any]] = plan.runs.compactMap { option in
            guard option.source != .free else { return nil }
            var session: [String: Any] = [
                "id": option.id.uuidString,
                "n": option.title,
                "d": option.detail,
                "src": option.source.rawValue,
                "st": (option.structure?.segments ?? []).map(step)
            ]
            if let date = option.date { session["day"] = Int(date.timeIntervalSince1970) }
            return session
        }
        return [
            "t": "plan",
            "v": version,
            "u": plan.units == .imperial ? "mi" : "km",
            "tol": Int(plan.coaching.toleranceSecondsPerKm.rounded()),
            "cue": Int(plan.coaching.paceCueDelaySeconds.rounded()),
            "cues": plan.coaching.paceCuesEnabled ? 1 : 0,
            "s": sessions
        ]
    }

    static func step(_ segment: RunSegment) -> [String: Any] {
        var meters = 0, seconds = 0
        switch segment.length {
        case .distance(let value): meters = Int(value.rounded())
        case .duration(let value): seconds = Int(value.rounded())
        }
        let code: String
        switch segment.kind {
        case .warmUp: code = "u"
        case .work: code = "w"
        case .recovery: code = "r"
        case .coolDown: code = "c"
        case .steady: code = "s"
        }
        return [
            "k": code,
            "l": segment.label ?? "",
            "m": meters,
            "sec": seconds,
            "f": Int((segment.targetPace?.fastest.secondsPerKm ?? 0).rounded()),
            "sl": Int((segment.targetPace?.slowest.secondsPerKm ?? 0).rounded()),
            "g": segment.paceIsGuide == true ? 1 : 0
        ]
    }

    public static func ackMessage(resultId: String) -> [String: Any] { ["t": "ack", "rid": resultId] }

    // MARK: Watch → phone

    /// What kind of message the watch sent ("hello", "result").
    public static func type(of message: [String: Any]) -> String? { message["t"] as? String }

    /// A finished run from the watch as the same result the Apple Watch sends. `option` is the
    /// planned session or saved workout it was (its structure lines up with the steps); nil for a
    /// free run or one no longer on the phone.
    public static func result(from message: [String: Any], option: WatchRunOption?, units: UnitSystem) -> WatchRunResult? {
        guard type(of: message) == "result", let rid = message["rid"] as? String, !rid.isEmpty,
              let start = number(message["start"]), let end = number(message["end"]) else { return nil }
        let duration = number(message["dur"]) ?? max(end - start, 0)
        let distance = number(message["dist"]) ?? 0
        guard duration > 0 else { return nil }
        let averageHR = number(message["hr"]).flatMap { $0 > 0 ? $0 : nil }
        let maxHR = number(message["hrx"]).flatMap { $0 > 0 ? $0 : nil }

        let segments = option?.structure?.segments ?? []
        var results: [SegmentResult] = []
        var inTarget = 0.0, targeted = 0.0
        for raw in (message["seg"] as? [Any]) ?? [] {
            guard let step = raw as? [String: Any], let index = number(step["i"]).map(Int.init),
                  segments.indices.contains(index) else { continue }
            let segment = segments[index]
            let seconds = number(step["dur"]) ?? 0
            let meters = number(step["dist"]) ?? 0
            let onTarget = number(step["in"]) ?? 0
            let measured = number(step["ms"]) ?? 0
            results.append(SegmentResult(index: index, segment: segment, durationSeconds: seconds, distanceMeters: meters,
                                         averagePace: meters > 20 && seconds > 0 ? Pace(metersPerSecond: meters / seconds) : nil,
                                         secondsInTarget: onTarget, secondsMeasured: measured))
            if segment.kind == .work, segment.targetPace != nil, segment.paceIsGuide != true {
                inTarget += onTarget
                targeted += measured
            }
        }

        // Splits per km or mile.
        let unitMeters = units == .imperial ? 1609.344 : 1000
        var splits: [Split] = []
        var elapsed = 0.0
        for (offset, raw) in ((message["spl"] as? [Any]) ?? []).enumerated() {
            guard let values = raw as? [Any], let seconds = values.first.flatMap(number), seconds > 0 else { continue }
            elapsed += seconds
            let hr = values.count > 1 ? number(values[1]).flatMap { $0 > 0 ? $0 : nil } : nil
            splits.append(Split(index: offset + 1, durationSeconds: seconds,
                                pace: Pace(secondsPerKm: seconds / unitMeters * 1000),
                                averagePace: Pace(secondsPerKm: elapsed / (unitMeters * Double(offset + 1)) * 1000),
                                averageHeartRate: hr))
        }

        // Laps pressed once the planned steps were done (or on a free run).
        var laps: [Lap] = []
        var lapEnd = 0.0
        for (offset, raw) in ((message["lap"] as? [Any]) ?? []).enumerated() {
            guard let values = raw as? [Any], let seconds = values.first.flatMap(number) else { continue }
            lapEnd += seconds
            let meters = values.count > 1 ? number(values[1]) ?? 0 : 0
            let hr = values.count > 2 ? number(values[2]).flatMap { $0 > 0 ? $0 : nil } : nil
            laps.append(Lap(index: offset + 1, durationSeconds: seconds, distanceMeters: meters, averageHeartRate: hr, endElapsedSeconds: lapEnd))
        }

        let summary = RunSummary(durationSeconds: duration, distanceMeters: distance,
                                 averagePace: distance > 50 ? Pace(metersPerSecond: distance / duration) : nil,
                                 splits: splits, segments: results, timeInTargetSeconds: inTarget, targetedSeconds: targeted,
                                 averageHeartRate: averageHR, maxHeartRate: maxHR, laps: laps.isEmpty ? nil : laps)
        let title = (message["n"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? option?.title ?? "Garmin run"
        let runOption = option ?? WatchRunOption(id: stableId("option-" + rid), source: .free, title: title)
        return WatchRunResult(id: stableId(rid), option: runOption,
                              startedAt: Date(timeIntervalSince1970: start), finishedAt: Date(timeIntervalSince1970: end),
                              summary: summary, effort: runOption.typicalEffort)
    }

    /// The session id the watch's result refers to.
    public static func sessionId(in message: [String: Any]) -> UUID? {
        (message["id"] as? String).flatMap(UUID.init(uuidString:))
    }

    /// The same id every time for the same text (so a result sent twice is saved once).
    public static func stableId(_ text: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((a >> (UInt64(i) * 8)) & 0xff)
            bytes[i + 8] = UInt8((b >> (UInt64(i) * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50 // version 5 style
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Numbers arrive as Int, Double or NSNumber depending on the platform.
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as Int32: return Double(value)
        case let value as Float: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }
}
