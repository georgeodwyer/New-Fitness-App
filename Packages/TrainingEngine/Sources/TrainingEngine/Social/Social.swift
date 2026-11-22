import Foundation

/// Hides where a run starts and ends before friends see the map: every point within
/// `radius` metres (straight line) of the first or last point is removed, so a loop from
/// home never shows home, even where it passes by mid-run. The rest is thinned to at most
/// `maxPoints` and rounded to 5 decimal places (about a metre).
public enum RoutePrivacy {
    public static let radius = 200.0
    public static let maxPoints = 400

    /// [[latitude, longitude], ...], or nil when too little is left to draw.
    public static func trimmed(_ route: [RoutePoint], radius: Double = radius, maxPoints: Int = maxPoints) -> [[Double]]? {
        guard let first = route.first, let last = route.last, route.count >= 2 else { return nil }
        let kept = route.filter { point in
            Geo.distance(point.latitude, point.longitude, first.latitude, first.longitude) >= radius
                && Geo.distance(point.latitude, point.longitude, last.latitude, last.longitude) >= radius
        }
        guard kept.count >= 2 else { return nil }
        let step = max(1, Int((Double(kept.count) / Double(max(maxPoints, 2))).rounded(.up)))
        var thinned = stride(from: 0, to: kept.count, by: step).map { kept[$0] }
        if let end = kept.last, thinned.last != end { thinned.append(end) }
        return thinned.map { [round5($0.latitude), round5($0.longitude)] }
    }

    private static func round5(_ value: Double) -> Double { (value * 100_000).rounded() / 100_000 }
}

/// Usernames: 3–20 lower-case letters, numbers or underscores (the server checks again).
public enum Username {
    public static func normalised(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Why a username can't be used, or nil when it's fine.
    public static func problem(_ text: String) -> String? {
        let name = normalised(text)
        if name.count < 3 { return "At least 3 characters" }
        if name.count > 20 { return "20 characters at most" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) { return "Letters, numbers and underscores only" }
        return nil
    }
}

/// Friend codes (8 characters, no 0/O or 1/I) and invite links: kinetix://friend/CODE.
public enum FriendLink {
    static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func normalisedCode(_ text: String) -> String? {
        let code = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        return code.count == 8 && code.allSatisfy(alphabet.contains) ? code : nil
    }

    public static func url(code: String) -> URL? { URL(string: "kinetix://friend/\(code)") }

    /// The code from an invite link (or a pasted code), else nil.
    public static func code(from url: URL) -> String? {
        guard url.scheme == "kinetix", url.host == "friend" else { return nil }
        return normalisedCode(url.lastPathComponent)
    }

    /// A pasted link or code.
    public static func code(fromText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let code = code(from: url) { return code }
        return normalisedCode(trimmed)
    }
}
