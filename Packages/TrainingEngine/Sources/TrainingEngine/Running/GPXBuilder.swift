import Foundation

/// Builds a GPX 1.1 file from a recorded run (for uploading to Strava and other services).
///
/// Point times are the run's start plus the active-running time at which each point was
/// recorded, so pauses are closed up. Heart rate, when recorded, is attached to each point
/// using the Garmin TrackPointExtension that Strava reads.
public enum GPXBuilder {
    public static func gpx(name: String, start: Date, route: [RoutePoint], heartRate: [HeartRateSample] = [],
                           creator: String = "Kinetix") -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let sortedHR = heartRate.sorted { $0.elapsed < $1.elapsed }

        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="\#(escape(creator))" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">"#,
            "  <metadata><time>\(formatter.string(from: start))</time></metadata>",
            "  <trk>",
            "    <name>\(escape(name))</name>",
            "    <type>running</type>",
            "    <trkseg>"
        ]
        for point in route {
            let time = formatter.string(from: start.addingTimeInterval(point.elapsed))
            var line = #"      <trkpt lat="\#(coordinate(point.latitude))" lon="\#(coordinate(point.longitude))"><time>\#(time)</time>"#
            if let bpm = nearestHeartRate(to: point.elapsed, in: sortedHR) {
                line += "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(Int(bpm.rounded()))</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>"
            }
            line += "</trkpt>"
            lines.append(line)
        }
        lines += ["    </trkseg>", "  </trk>", "</gpx>"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The closest heart-rate sample within 15 s, if any.
    static func nearestHeartRate(to elapsed: Double, in samples: [HeartRateSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        // Binary search for the first sample at or after `elapsed`.
        var low = 0, high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].elapsed < elapsed { low = mid + 1 } else { high = mid }
        }
        let candidates = [low - 1, low].filter { $0 >= 0 && $0 < samples.count }.map { samples[$0] }
        guard let best = candidates.min(by: { abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed) }),
              abs(best.elapsed - elapsed) <= 15 else { return nil }
        return best.bpm
    }

    private static func coordinate(_ value: Double) -> String {
        // 7 decimal places ≈ 1 cm; POSIX formatting regardless of locale.
        let scaled = (value * 10_000_000).rounded() / 10_000_000
        return String(describing: scaled)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
