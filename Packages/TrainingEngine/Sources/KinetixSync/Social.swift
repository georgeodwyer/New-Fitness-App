import Foundation

/// Friends: usernames, friend requests, shared sessions, the weekly leaderboard,
/// head-to-head and challenges. The server side is supabase/friends.sql.
public struct SocialAPI: Sendable {
    public let client: SupabaseClient

    public init(client: SupabaseClient) { self.client = client }

    // MARK: Profile

    public func myProfile() async throws -> SocialProfile? {
        try decode(SocialProfile?.self, await client.rpc("my_social_profile"))
    }

    public func claimUsername(_ username: String, displayName: String) async throws -> SocialProfile {
        try decode(SocialProfile.self, await client.rpc("claim_username", params: [
            "p_username": .string(username), "p_display_name": .string(displayName)]))
    }

    public func setSharing(_ on: Bool) async throws {
        _ = try await client.rpc("set_sharing", params: ["p_sharing": .bool(on)])
    }

    // MARK: People

    public func search(_ query: String) async throws -> [SocialPerson] {
        try decode([SocialPerson].self, await client.rpc("search_users", params: ["p_query": .string(query)]))
    }

    public func find(code: String) async throws -> SocialPerson? {
        try decode([SocialPerson].self, await client.rpc("find_by_code", params: ["p_code": .string(code)])).first
    }

    /// Returns the new relation: `.friend` if they'd already asked you, else `.outgoing`.
    @discardableResult
    public func sendRequest(to user: UUID) async throws -> SocialPerson.Relation {
        let text = try decode(String.self, await client.rpc("send_friend_request", params: ["p_user": .id(user)]))
        return SocialPerson.Relation(rawValue: text) ?? .outgoing
    }

    public func respond(to user: UUID, accept: Bool) async throws {
        _ = try await client.rpc("respond_friend_request", params: ["p_user": .id(user), "p_accept": .bool(accept)])
    }

    public func remove(_ user: UUID) async throws {
        _ = try await client.rpc("remove_friend", params: ["p_user": .id(user)])
    }

    public func friends() async throws -> [SocialPerson] {
        try decode([SocialPerson].self, await client.rpc("list_friends"))
    }

    public func block(_ user: UUID) async throws {
        _ = try await client.rpc("block_user", params: ["p_user": .id(user)])
    }

    public func unblock(_ user: UUID) async throws {
        _ = try await client.rpc("unblock_user", params: ["p_user": .id(user)])
    }

    public func blocked() async throws -> [SocialPerson] {
        try decode([SocialPerson].self, await client.rpc("list_blocked"))
    }

    public func report(_ user: UUID, session: UUID?, reason: String) async throws {
        _ = try await client.rpc("report_user", params: [
            "p_user": .id(user), "p_session": session.map(JSONValue.id) ?? .null, "p_reason": .string(reason)])
    }

    // MARK: Sharing

    public func share(_ sessions: [SharedSessionUpload]) async throws {
        for start in stride(from: 0, to: sessions.count, by: 100) {
            try await client.upsert("shared_sessions", rows: Array(sessions[start..<min(start + 100, sessions.count)]), onConflict: "id")
        }
    }

    public func unshare(_ ids: [UUID]) async throws {
        try await client.delete("shared_sessions", ids: ids)
    }

    public func savePoints(_ weeks: [WeeklyPointsUpload]) async throws {
        try await client.upsert("weekly_points", rows: weeks, onConflict: "user_id,week_start")
    }

    // MARK: Friends' activity

    public func feed(before: Date? = nil, limit: Int = 30) async throws -> [FeedItem] {
        try decode([FeedItem].self, await client.rpc("friend_feed", params: [
            "p_before": before.map { .string(SyncCoding.formatDate($0)) } ?? .null, "p_limit": .number(Double(limit))]))
    }

    public func leaderboard(week: Date, calendar: Calendar) async throws -> [LeaderboardRow] {
        try decode([LeaderboardRow].self, await client.rpc("leaderboard", params: ["p_week": .string(SocialDay.string(week, calendar: calendar))]))
    }

    public func headToHead(with user: UUID, week: Date, weeks: Int = 8, calendar: Calendar) async throws -> [HeadToHeadWeek] {
        try decode([HeadToHeadWeek].self, await client.rpc("head_to_head", params: [
            "p_user": .id(user), "p_week": .string(SocialDay.string(week, calendar: calendar)), "p_weeks": .number(Double(weeks))]))
    }

    // MARK: Challenges

    @discardableResult
    public func createChallenge(title: String, metric: FriendChallenge.Metric, target: Double, starts: Date, ends: Date,
                                friends: [UUID], calendar: Calendar) async throws -> UUID {
        let text = try decode(String.self, await client.rpc("create_challenge", params: [
            "p_title": .string(title), "p_metric": .string(metric.rawValue), "p_target": .number(target),
            "p_starts": .string(SocialDay.string(starts, calendar: calendar)), "p_ends": .string(SocialDay.string(ends, calendar: calendar)),
            "p_friends": .array(friends.map(JSONValue.id))]))
        guard let id = UUID(uuidString: text) else { throw SupabaseError.invalidResponse }
        return id
    }

    public func respondToChallenge(_ id: UUID, join: Bool) async throws {
        _ = try await client.rpc("respond_challenge", params: ["p_id": .id(id), "p_join": .bool(join)])
    }

    public func updateProgress(_ values: [UUID: Double]) async throws {
        guard !values.isEmpty else { return }
        let list = values.map { JSONValue.object(["id": .id($0.key), "value": .number($0.value)]) }
        _ = try await client.rpc("update_challenge_progress", params: ["p_values": .array(list)])
    }

    public func challenges() async throws -> [FriendChallenge] {
        try decode([FriendChallenge].self, await client.rpc("my_challenges"))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try SyncCoding.decoder.decode(type, from: data.isEmpty ? Data("null".utf8) : data)
    }
}

extension JSONValue {
    static func id(_ value: UUID) -> JSONValue { .string(value.uuidString.lowercased()) }
}

/// Postgres `date` values ("2026-11-16") in the app's calendar.
public enum SocialDay {
    public static func string(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func date(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - Models

public struct SocialProfile: Codable, Equatable, Sendable {
    public var userId: UUID
    public var username: String
    public var displayName: String
    public var friendCode: String
    public var sharing: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", username, displayName = "display_name", friendCode = "friend_code", sharing
    }

    public init(userId: UUID, username: String, displayName: String, friendCode: String, sharing: Bool) {
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.friendCode = friendCode
        self.sharing = sharing
    }
}

public struct SocialPerson: Codable, Hashable, Sendable, Identifiable {
    public enum Relation: String, Codable, Hashable, Sendable { case friend, incoming, outgoing, none }

    public var userId: UUID
    public var username: String
    public var displayName: String
    public var relation: Relation?
    public var id: UUID { userId }
    /// The display name, or the username when there isn't one.
    public var name: String { displayName.isEmpty ? username : displayName }

    enum CodingKeys: String, CodingKey { case userId = "user_id", username, displayName = "display_name", relation }

    public init(userId: UUID, username: String, displayName: String, relation: Relation?) {
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.relation = relation
    }
}

/// A session as friends see it. Every key is always sent (the server needs the same keys in
/// each row of a batch).
public struct SharedSessionUpload: Encodable, Equatable, Sendable {
    public var id: UUID
    public var kind: String
    public var title: String
    public var startedAt: Date
    public var durationSeconds: Double
    public var distanceMeters: Double
    public var load: Double
    public var runType: String?
    public var averageHeartRate: Double?
    public var sets: Int
    public var route: [[Double]]?
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, title, startedAt = "started_at", durationSeconds = "duration_seconds", distanceMeters = "distance_meters"
        case load, runType = "run_type", averageHeartRate = "average_heart_rate", sets, route, updatedAt = "updated_at"
    }

    public init(id: UUID, kind: String, title: String, startedAt: Date, durationSeconds: Double, distanceMeters: Double, load: Double,
                runType: String?, averageHeartRate: Double?, sets: Int, route: [[Double]]?, updatedAt: Date) {
        self.id = id
        self.kind = kind
        self.title = title
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.load = load
        self.runType = runType
        self.averageHeartRate = averageHeartRate
        self.sets = sets
        self.route = route
        self.updatedAt = updatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(load, forKey: .load)
        if let runType { try container.encode(runType, forKey: .runType) } else { try container.encodeNil(forKey: .runType) }
        if let averageHeartRate { try container.encode(averageHeartRate, forKey: .averageHeartRate) } else { try container.encodeNil(forKey: .averageHeartRate) }
        try container.encode(sets, forKey: .sets)
        if let route { try container.encode(route, forKey: .route) } else { try container.encodeNil(forKey: .route) }
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct WeeklyPointsUpload: Encodable, Equatable, Sendable {
    public var weekStart: String
    public var points: Int
    public var planned: Int
    public var fullWeek: Int
    public var streak: Int
    public var load: Int
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start", points, planned, fullWeek = "full_week", streak, load, updatedAt = "updated_at"
    }

    public init(weekStart: String, points: Int, planned: Int, fullWeek: Int, streak: Int, load: Int, updatedAt: Date) {
        self.weekStart = weekStart
        self.points = points
        self.planned = planned
        self.fullWeek = fullWeek
        self.streak = streak
        self.load = load
        self.updatedAt = updatedAt
    }
}

public struct FeedItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var username: String
    public var displayName: String
    public var kind: String
    public var title: String
    public var startedAt: Date
    public var durationSeconds: Double
    public var distanceMeters: Double
    public var load: Double
    public var runType: String?
    public var averageHeartRate: Double?
    public var sets: Int
    public var route: [[Double]]?
    public var name: String { displayName.isEmpty ? username : displayName }

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", username, displayName = "display_name", kind, title, startedAt = "started_at"
        case durationSeconds = "duration_seconds", distanceMeters = "distance_meters", load, runType = "run_type"
        case averageHeartRate = "average_heart_rate", sets, route
    }
}

public struct LeaderboardRow: Decodable, Equatable, Sendable, Identifiable {
    public var userId: UUID
    public var username: String
    public var displayName: String
    public var points: Int
    public var planned: Int
    public var fullWeek: Int
    public var streak: Int
    public var load: Int
    public var isMe: Bool
    public var id: UUID { userId }
    public var name: String { displayName.isEmpty ? username : displayName }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", username, displayName = "display_name", points, planned, fullWeek = "full_week", streak, load, isMe = "is_me"
    }
}

public struct HeadToHeadWeek: Decodable, Equatable, Sendable, Identifiable {
    public var weekStart: String
    public var myPoints: Int
    public var theirPoints: Int
    public var id: String { weekStart }

    enum CodingKeys: String, CodingKey { case weekStart = "week_start", myPoints = "my_points", theirPoints = "their_points" }
}

public struct FriendChallenge: Decodable, Equatable, Sendable, Identifiable {
    public enum Metric: String, Codable, Sendable, CaseIterable { case runKilometres, gymSessions, activeDays, points }

    public struct Member: Decodable, Equatable, Sendable, Identifiable {
        public var userId: UUID
        public var username: String
        public var displayName: String
        public var joined: Bool
        public var value: Double
        public var id: UUID { userId }
        public var name: String { displayName.isEmpty ? username : displayName }

        enum CodingKeys: String, CodingKey { case userId = "user_id", username, displayName = "display_name", joined, value }
    }

    public var id: UUID
    public var title: String
    public var metric: Metric
    public var target: Double
    public var startsOn: String
    public var endsOn: String
    public var creator: UUID
    public var joined: Bool
    public var members: [Member]

    enum CodingKeys: String, CodingKey {
        case id, title, metric, target, startsOn = "starts_on", endsOn = "ends_on", creator, joined, members
    }
}
