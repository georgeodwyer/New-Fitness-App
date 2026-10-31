import Foundation

/// Builds a TCX file (Garmin Training Center) from a recorded run, for Strava. Unlike GPX it
/// carries laps (each rep and recovery its own lap, so Strava's Laps match Kinetix's parts)
/// and a distance at each point (so Strava's distance matches Kinetix's, track mode included).
public enum TCXBuilder {
    /// A lap: when it started (active seconds from the start) and how long it lasted.
    public struct LapSpan: Equatable, Sendable {
        public var start: Double
        public var duration: Double
        public var distanceMeters: Double
        /// A recovery or warm-up/cool-down (Resting) rather than work (Active).
        public var isRest: Bool

        public init(start: Double, duration: Double, distanceMeters: Double, isRest: Bool = false) {
            self.start = start
            self.duration = duration
            self.distanceMeters = distanceMeters
            self.isRest = isRest
        }
    }

    /// Laps from a run's parts (reps, recoveries…), else its hand-marked laps, else one lap.
    /// Anything after the last part (running on after the session) is a lap of its own.
    public static func laps(segments: [SegmentResult], laps: [Lap], durationSeconds: Double,
                            distanceMeters: Double) -> [LapSpan] {
        var result: [LapSpan] = []
        if !segments.isEmpty {
            var start = 0.0
            for segment in segments {
                result.append(LapSpan(start: start, duration: segment.durationSeconds, distanceMeters: segment.distanceMeters,
                                      isRest: segment.segment.kind != .work && segment.segment.kind != .steady))
                start += segment.durationSeconds
            }
        } else if !laps.isEmpty {
            var start = 0.0
            for lap in laps {
                result.append(LapSpan(start: start, duration: lap.durationSeconds, distanceMeters: lap.distanceMeters))
                start += lap.durationSeconds
            }
        }
        let covered = result.reduce(0) { $0 + $1.duration }
        let coveredDistance = result.reduce(0) { $0 + $1.distanceMeters }
        if durationSeconds - covered > 5 || result.isEmpty {
            result.append(LapSpan(start: covered, duration: max(0, durationSeconds - covered),
                                  distanceMeters: max(0, distanceMeters - coveredDistance)))
        }
        return result
    }

    public static func tcx(start: Date, route: [RoutePoint], heartRate: [HeartRateSample] = [], laps: [LapSpan],
                           distanceMeters: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let sortedHR = heartRate.sorted { $0.elapsed < $1.elapsed }

        // Distance at each point: along the route, scaled to the run's measured distance (which
        // leaves out GPS jumps, and follows the lane in track mode).
        var cumulative: [Double] = []
        var total = 0.0
        for (index, point) in route.enumerated() {
            if index > 0 {
                let previous = route[index - 1]
                total += Geo.distance(previous.latitude, previous.longitude, point.latitude, point.longitude)
            }
            cumulative.append(total)
        }
        let scale = total > 0 && distanceMeters > 0 ? distanceMeters / total : 1

        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">"#,
            "  <Activities>",
            #"    <Activity Sport="Running">"#,
            "      <Id>\(formatter.string(from: start))</Id>"
        ]
        for (index, lap) in laps.enumerated() {
            let isLast = index == laps.count - 1
            let end = lap.start + lap.duration
            lines.append(#"      <Lap StartTime="\#(formatter.string(from: start.addingTimeInterval(lap.start)))">"#)
            lines.append("        <TotalTimeSeconds>\(String(format: "%.1f", lap.duration))</TotalTimeSeconds>")
            lines.append("        <DistanceMeters>\(String(format: "%.1f", lap.distanceMeters))</DistanceMeters>")
            lines.append("        <Intensity>\(lap.isRest ? "Resting" : "Active")</Intensity>")
            lines.append("        <TriggerMethod>Manual</TriggerMethod>")
            lines.append("        <Track>")
            for (pointIndex, point) in route.enumerated()
            where point.elapsed >= lap.start && (point.elapsed < end || (isLast && point.elapsed >= lap.start)) {
                var line = "          <Trackpoint><Time>\(formatter.string(from: start.addingTimeInterval(point.elapsed)))</Time>"
                line += "<Position><LatitudeDegrees>\(coordinate(point.latitude))</LatitudeDegrees>"
                line += "<LongitudeDegrees>\(coordinate(point.longitude))</LongitudeDegrees></Position>"
                if let altitude = point.altitude { line += "<AltitudeMeters>\(String(format: "%.1f", altitude))</AltitudeMeters>" }
                line += "<DistanceMeters>\(String(format: "%.1f", cumulative[pointIndex] * scale))</DistanceMeters>"
                if let bpm = GPXBuilder.nearestHeartRate(to: point.elapsed, in: sortedHR) {
                    line += "<HeartRateBpm><Value>\(Int(bpm.rounded()))</Value></HeartRateBpm>"
                }
                line += "</Trackpoint>"
                lines.append(line)
            }
            lines.append("        </Track>")
            lines.append("      </Lap>")
        }
        lines += [#"      <Creator xsi:type="Device_t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Name>Kinetix</Name></Creator>"#,
                  "    </Activity>", "  </Activities>", "</TrainingCenterDatabase>"]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func coordinate(_ value: Double) -> String {
        String(describing: (value * 10_000_000).rounded() / 10_000_000)
    }
}
