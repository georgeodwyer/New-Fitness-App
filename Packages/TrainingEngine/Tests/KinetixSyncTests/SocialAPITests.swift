import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KinetixSync

final class SocialAPITests: XCTestCase {
    private let config = SupabaseConfig(url: URL(string: "https://abc.supabase.co")!, anonKey: "anon-key")
    private let me = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
    private let ben = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000002")!

    private func api(_ replies: [StubTransport.Reply]) -> (SocialAPI, StubTransport) {
        let transport = StubTransport(replies)
        let session = AuthSession(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(3600), userId: me, email: nil)
        return (SocialAPI(client: SupabaseClient(config: config, transport: transport, session: session)), transport)
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testClaimUsername() async throws {
        let (api, transport) = api([.init(status: 200, body: #"{"user_id":"aaaaaaaa-0000-0000-0000-000000000001","username":"ann","display_name":"Ann","friend_code":"GXQDRN26","sharing":true}"#)])
        let profile = try await api.claimUsername("ann", displayName: "Ann")
        XCTAssertEqual(profile.friendCode, "GXQDRN26")
        XCTAssertEqual(profile.userId, me)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/rest/v1/rpc/claim_username")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        let sent = try body(request)
        XCTAssertEqual(sent["p_username"] as? String, "ann")
        XCTAssertEqual(sent["p_display_name"] as? String, "Ann")
    }

    func testNoProfileYetIsNil() async throws {
        let (api, _) = api([.init(status: 200, body: "null")])
        let profile = try await api.myProfile()
        XCTAssertNil(profile)
    }

    func testServerMessageIsShown() async {
        let (api, _) = api([.init(status: 400, body: #"{"code":"P0001","message":"That username is taken"}"#)])
        do {
            _ = try await api.claimUsername("ann", displayName: "")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? SupabaseError, .server(status: 400, message: "That username is taken"))
        }
    }

    func testSendRequestAndVoidCalls() async throws {
        let (api, transport) = api([.init(status: 200, body: #""friend""#), .init(status: 204, body: "")])
        let relation = try await api.sendRequest(to: ben)
        XCTAssertEqual(relation, .friend)
        try await api.block(ben)
        XCTAssertEqual(try body(transport.requests[1])["p_user"] as? String, "bbbbbbbb-0000-0000-0000-000000000002")
    }

    func testFriendsListDecodes() async throws {
        let (api, _) = api([.init(status: 200, body: #"[{"user_id":"bbbbbbbb-0000-0000-0000-000000000002","username":"ben","display_name":"","relation":"incoming"}]"#)])
        let friends = try await api.friends()
        XCTAssertEqual(friends.first?.relation, .incoming)
        XCTAssertEqual(friends.first?.name, "ben")
    }

    func testFeedDecodesPostgresDatesAndRoutes() async throws {
        let row = #"{"id":"cccccccc-0000-0000-0000-000000000003","user_id":"bbbbbbbb-0000-0000-0000-000000000002","username":"ben","display_name":"Ben","kind":"run","title":"Easy run","started_at":"2026-11-22T16:13:38.123456+00:00","duration_seconds":2400,"distance_meters":8000,"load":120,"run_type":"easy","average_heart_rate":null,"sets":0,"route":[[51.5,-0.1],[51.501,-0.1]]}"#
        let (api, transport) = api([.init(status: 200, body: "[\(row)]")])
        let feed = try await api.feed(limit: 10)
        XCTAssertEqual(feed.first?.route?.count, 2)
        XCTAssertNil(feed.first?.averageHeartRate)
        XCTAssertEqual(feed.first?.startedAt.timeIntervalSince1970 ?? 0, 1_795_364_018.123, accuracy: 0.01)
        let sent = try body(transport.requests[0])
        XCTAssertTrue(sent["p_before"] is NSNull)
        XCTAssertEqual((sent["p_limit"] as? NSNumber)?.intValue, 10)
    }

    func testShareSendsEveryKeyIncludingNulls() async throws {
        let (api, transport) = api([.init(status: 201, body: "")])
        let session = SharedSessionUpload(id: ben, kind: "gym", title: "Legs", startedAt: Date(timeIntervalSince1970: 0), durationSeconds: 3000,
                                          distanceMeters: 0, load: 200, runType: nil, averageHeartRate: nil, sets: 18, route: nil,
                                          updatedAt: Date(timeIntervalSince1970: 0))
        try await api.share([session])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/rest/v1/shared_sessions?on_conflict=id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [[String: Any]])
        XCTAssertEqual(Set(rows[0].keys), ["id", "kind", "title", "started_at", "duration_seconds", "distance_meters", "load",
                                           "run_type", "average_heart_rate", "sets", "route", "updated_at"])
        XCTAssertTrue(rows[0]["route"] is NSNull)
    }

    func testNothingToShareSendsNothing() async throws {
        let (api, transport) = api([])
        try await api.share([])
        try await api.unshare([])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testUnshareDeletesById() async throws {
        let (api, transport) = api([.init(status: 204, body: "")])
        try await api.unshare([ben])
        XCTAssertEqual(transport.requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(transport.requests.first?.url?.absoluteString,
                       "https://abc.supabase.co/rest/v1/shared_sessions?id=in.(bbbbbbbb-0000-0000-0000-000000000002)")
    }

    func testLeaderboardSendsTheWeekAsADate() async throws {
        let (api, transport) = api([.init(status: 200, body: #"[{"user_id":"aaaaaaaa-0000-0000-0000-000000000001","username":"ann","display_name":"Ann","points":150,"planned":60,"full_week":50,"streak":20,"load":20,"is_me":true}]"#)])
        let week = utc.date(from: DateComponents(year: 2026, month: 11, day: 16))!
        let rows = try await api.leaderboard(week: week, calendar: utc)
        XCTAssertEqual(rows.first?.points, 150)
        XCTAssertEqual(try body(transport.requests[0])["p_week"] as? String, "2026-11-16")
    }

    func testChallenges() async throws {
        let json = #"[{"id":"d15bf0f8-239d-46a2-bdd8-7340886af689","title":"50 km","metric":"runKilometres","target":50,"starts_on":"2026-11-22","ends_on":"2026-12-22","creator":"aaaaaaaa-0000-0000-0000-000000000001","joined":true,"members":[{"user_id":"bbbbbbbb-0000-0000-0000-000000000002","username":"ben","display_name":"Ben B","joined":true,"value":20}]}]"#
        let (api, transport) = api([.init(status: 200, body: #""d15bf0f8-239d-46a2-bdd8-7340886af689""#), .init(status: 200, body: json)])
        let start = utc.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        let id = try await api.createChallenge(title: "50 km", metric: .runKilometres, target: 50, starts: start,
                                               ends: utc.date(byAdding: .day, value: 30, to: start)!, friends: [ben], calendar: utc)
        XCTAssertEqual(id.uuidString.lowercased(), "d15bf0f8-239d-46a2-bdd8-7340886af689")
        let sent = try body(transport.requests[0])
        XCTAssertEqual(sent["p_ends"] as? String, "2026-12-22")
        XCTAssertEqual(sent["p_friends"] as? [String], ["bbbbbbbb-0000-0000-0000-000000000002"])
        let list = try await api.challenges()
        XCTAssertEqual(list.first?.members.first?.name, "Ben B")
        XCTAssertEqual(SocialDay.date(list[0].endsOn, calendar: utc), utc.date(byAdding: .day, value: 30, to: start))
    }
}
