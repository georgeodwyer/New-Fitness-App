import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KinetixSync

final class StravaTests: XCTestCase {
    private let config = StravaConfig(clientID: "12345", tokenExchangeURL: URL(string: "https://abc.supabase.co/functions/v1/strava-token")!,
                                      supabaseAnonKey: "anon")
    private let tokenJSON = #"{"token_type":"Bearer","access_token":"a1","refresh_token":"r1","expires_at":4102444800,"athlete":{"id":7,"firstname":"Sam","lastname":"Runner"}}"#

    private func connectedClient(_ transport: StubTransport, expiresAt: Date = Date().addingTimeInterval(3600)) -> StravaClient {
        StravaClient(config: config, transport: transport,
                     tokens: StravaTokens(accessToken: "a1", refreshToken: "r1", expiresAt: expiresAt, athleteId: 7, athleteName: "Sam Runner"),
                     sleep: { _ in })
    }

    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }

    func testConfigFromInfo() {
        let info: [String: Any] = ["StravaClientID": "12345", "SupabaseURL": "https://abc.supabase.co", "SupabaseAnonKey": "k"]
        XCTAssertEqual(StravaConfig(info: info)?.tokenExchangeURL.absoluteString, "https://abc.supabase.co/functions/v1/strava-token")
        var missingSupabase = info
        missingSupabase["SupabaseURL"] = ""
        XCTAssertNil(StravaConfig(info: missingSupabase), "The token exchange needs Supabase or a client secret")
        var direct = missingSupabase
        direct["StravaClientSecret"] = "shh"
        XCTAssertEqual(StravaConfig(info: direct)?.isDirect, true)
        XCTAssertEqual(StravaConfig(info: direct)?.tokenExchangeURL, StravaConfig.directTokenURL)
        direct["StravaClientSecret"] = "$(STRAVA_CLIENT_SECRET)"
        XCTAssertNil(StravaConfig(info: direct), "An unfilled build setting isn't a secret")
        var both = info
        both["StravaClientSecret"] = "shh"
        XCTAssertEqual(StravaConfig(info: both)?.isDirect, false, "Supabase is preferred when set up")
        var badID = info
        badID["StravaClientID"] = "$(STRAVA_CLIENT_ID)"
        XCTAssertNil(StravaConfig(info: badID))
    }

    func testAuthorizeURLAndCallback() throws {
        let client = StravaClient(config: config, transport: StubTransport([]))
        let url = client.authorizeURL(state: "xyz")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "redirect_uri" }?.value, "kinetix://localhost/strava")
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, "read,activity:read_all,activity:write")

        let good = URL(string: "kinetix://localhost/strava?state=xyz&code=abc&scope=read,activity:write")!
        XCTAssertEqual(try StravaClient.authorizationCode(from: good, expectedState: "xyz"), "abc")
        XCTAssertThrowsError(try StravaClient.authorizationCode(from: good, expectedState: "other")) {
            XCTAssertEqual($0 as? StravaError, .invalidCallback)
        }
        let noWrite = URL(string: "kinetix://localhost/strava?state=xyz&code=abc&scope=read")!
        XCTAssertThrowsError(try StravaClient.authorizationCode(from: noWrite, expectedState: "xyz")) {
            XCTAssertEqual($0 as? StravaError, .missingUploadPermission)
        }
        let denied = URL(string: "kinetix://localhost/strava?state=xyz&error=access_denied")!
        XCTAssertThrowsError(try StravaClient.authorizationCode(from: denied, expectedState: "xyz")) {
            XCTAssertEqual($0 as? StravaError, .denied)
        }
    }

    func testConnectExchangesCodeThroughEdgeFunction() async throws {
        let transport = StubTransport([.init(status: 200, body: tokenJSON)])
        let client = StravaClient(config: config, transport: transport)
        let tokens = try await client.connect(code: "abc")
        XCTAssertEqual(tokens.athleteName, "Sam Runner")
        XCTAssertEqual(tokens.expiresAt, Date(timeIntervalSince1970: 4102444800))
        let request = transport.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/functions/v1/strava-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon")
        let sent = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
        XCTAssertEqual(sent, ["grant_type": "authorization_code", "code": "abc"])
        XCTAssertFalse(body(request).contains("secret"))
    }

    func testUploadPollsUntilActivityIsReady() async throws {
        let transport = StubTransport([
            .init(status: 201, body: #"{"id":99,"status":"Your activity is still being processed.","activity_id":null,"error":null}"#),
            .init(status: 200, body: #"{"id":99,"status":"Your activity is still being processed.","activity_id":null,"error":null}"#),
            .init(status: 200, body: #"{"id":99,"status":"Your activity is ready.","activity_id":555,"error":null}"#)
        ])
        let client = connectedClient(transport)
        let activity = try await client.uploadGPX("<gpx/>", name: "Tempo", description: "Planned by Kinetix", externalId: "kinetix-run-1")
        XCTAssertEqual(activity, 555)
        XCTAssertEqual(transport.requests.count, 3)
        let upload = transport.requests[0]
        XCTAssertEqual(upload.url?.absoluteString, "https://www.strava.com/api/v3/uploads")
        XCTAssertEqual(upload.value(forHTTPHeaderField: "Authorization"), "Bearer a1")
        XCTAssertTrue(upload.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let text = body(upload)
        XCTAssertTrue(text.contains("name=\"data_type\"\r\n\r\ngpx\r\n"))
        XCTAssertTrue(text.contains("filename=\"kinetix-run-1.gpx\""))
        XCTAssertTrue(text.contains("<gpx/>"))
        XCTAssertTrue(text.hasSuffix("--\r\n"))
        XCTAssertEqual(transport.requests[1].url?.absoluteString, "https://www.strava.com/api/v3/uploads/99")
    }

    func testDuplicateUploadLinksExistingActivity() async throws {
        let transport = StubTransport([
            .init(status: 201, body: #"{"id":99,"activity_id":null,"error":"kinetix-run-1.gpx duplicate of activity 4242","status":"There was an error processing your activity."}"#)
        ])
        let activity = try await connectedClient(transport).uploadGPX("<gpx/>", name: "Run", description: nil, externalId: "kinetix-run-1")
        XCTAssertEqual(activity, 4242)
    }

    func testUploadErrorIsReported() async {
        let transport = StubTransport([.init(status: 201, body: #"{"id":99,"activity_id":null,"error":"Empty file","status":"error"}"#)])
        do {
            _ = try await connectedClient(transport).uploadGPX("", name: "Run", description: nil, externalId: "x")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StravaError, .uploadFailed("Empty file"))
        }
    }

    func testExpiredTokenIsRefreshedFirst() async throws {
        let refreshed = #"{"access_token":"a2","refresh_token":"r2","expires_at":4102444800}"#
        let transport = StubTransport([
            .init(status: 200, body: refreshed),
            .init(status: 201, body: #"{"id":321,"name":"Strength"}"#)
        ])
        let client = connectedClient(transport, expiresAt: Date().addingTimeInterval(-10))
        let utc = TimeZone(identifier: "UTC")!
        let id = try await client.createActivity(name: "Upper body", sportType: "WeightTraining",
                                                 start: Date(timeIntervalSince1970: 1_760_000_000), elapsedSeconds: 3000,
                                                 description: "3 × 8 bench & rows", timeZone: utc)
        XCTAssertEqual(id, 321)
        let sent = try JSONDecoder().decode([String: String].self, from: transport.requests[0].httpBody!)
        XCTAssertEqual(sent, ["grant_type": "refresh_token", "refresh_token": "r1"])
        let create = transport.requests[1]
        XCTAssertEqual(create.value(forHTTPHeaderField: "Authorization"), "Bearer a2")
        XCTAssertEqual(body(create), "name=Upper%20body&sport_type=WeightTraining&start_date_local=2025-10-09T08%3A53%3A20Z&elapsed_time=3000&description=3%20%C3%97%208%20bench%20%26%20rows")
        let tokens = await client.tokens
        XCTAssertEqual(tokens?.athleteName, "Sam Runner", "Refresh keeps the athlete's name")
        XCTAssertEqual(tokens?.refreshToken, "r2")
    }

    func testRevokedAccessDisconnects() async {
        let transport = StubTransport([.init(status: 400, body: #"{"message":"Bad Request","errors":[{"field":"refresh_token","code":"invalid"}]}"#)])
        let client = connectedClient(transport, expiresAt: Date().addingTimeInterval(-10))
        do {
            _ = try await client.createActivity(name: "x", sportType: "WeightTraining", start: Date(), elapsedSeconds: 60, description: nil)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StravaError, .notConnected)
        }
        let tokens = await client.tokens
        XCTAssertNil(tokens)
    }

    func testTransientErrors() {
        XCTAssertTrue(StravaError.server(status: 429, message: "").isTransient)
        XCTAssertTrue(StravaError.network("offline").isTransient)
        XCTAssertFalse(StravaError.uploadFailed("bad").isTransient)
        XCTAssertEqual(StravaUploadStatus(id: 1, error: "a.gpx duplicate of activity 12345.").duplicateActivityId, 12345)
    }

    func testDirectExchangeSendsClientSecretToStrava() async throws {
        let transport = StubTransport([.init(status: 200, body: tokenJSON)])
        let client = StravaClient(config: .direct(clientID: "12345", clientSecret: "shh"), transport: transport)
        let tokens = try await client.connect(code: "abc", scopes: ["read", "activity:read_all", "activity:write"])
        XCTAssertTrue(tokens.canReadActivities)
        let request = transport.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "https://www.strava.com/oauth/token")
        XCTAssertEqual(body(request), "client_id=12345&client_secret=shh&code=abc&grant_type=authorization_code")
        XCTAssertNil(request.value(forHTTPHeaderField: "apikey"))
    }

    func testGrantedScopes() {
        let url = URL(string: "kinetix://localhost/strava?state=x&code=c&scope=read,activity:write")!
        XCTAssertEqual(StravaClient.grantedScopes(from: url), ["read", "activity:write"])
        XCTAssertFalse(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(), scopes: ["read", "activity:write"]).canReadActivities)
        XCTAssertFalse(StravaTokens(accessToken: "a", refreshToken: "r", expiresAt: Date()).canReadActivities)
    }

    func testRefreshKeepsScopes() async throws {
        let transport = StubTransport([.init(status: 200, body: tokenJSON), .init(status: 200, body: "[]")])
        let client = StravaClient(config: config, transport: transport,
                                  tokens: StravaTokens(accessToken: "old", refreshToken: "r0", expiresAt: Date().addingTimeInterval(-60),
                                                       scopes: ["activity:read_all"]),
                                  sleep: { _ in })
        _ = try await client.activities(after: Date(timeIntervalSince1970: 1_700_000_000))
        let tokens = await client.tokens
        XCTAssertEqual(tokens?.accessToken, "a1")
        XCTAssertEqual(tokens?.scopes, ["activity:read_all"])
    }

    func testActivitiesAreListedAndDecoded() async throws {
        let json = """
        [{"id": 111, "name": "Morning Run", "sport_type": "Run", "start_date": "2026-10-15T07:30:00Z",
          "elapsed_time": 1900, "moving_time": 1800, "distance": 5012.5, "average_heartrate": 151.2,
          "max_heartrate": 172, "external_id": "garmin_ping_123", "map": {"summary_polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"}},
         {"id": 112, "name": "Kinetix run", "type": "Run", "start_date": "2026-10-14T07:30:00Z",
          "elapsed_time": 1200, "moving_time": 1200, "distance": 3000, "external_id": "kinetix-ABC.gpx", "map": {"summary_polyline": null}},
         {"id": 113, "name": "Commute", "sport_type": "EBikeRide", "start_date": "2026-10-13T17:00:00Z",
          "elapsed_time": 900, "moving_time": 850, "distance": 4000}]
        """
        let transport = StubTransport([.init(status: 200, body: json)])
        let activities = try await connectedClient(transport).activities(after: Date(timeIntervalSince1970: 1_760_000_000), perPage: 50)
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.path, "/api/v3/athlete/activities")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "after" }?.value, "1760000000")
        XCTAssertEqual(items.first { $0.name == "per_page" }?.value, "50")

        XCTAssertEqual(activities.count, 3)
        XCTAssertEqual(activities[0].category, .run)
        XCTAssertEqual(activities[0].movingTime, 1800)
        XCTAssertEqual(activities[0].startDate, Date(timeIntervalSince1970: 1_792_049_400))
        XCTAssertFalse(activities[0].isFromKinetix)
        XCTAssertEqual(activities[0].routeCoordinates.count, 3)
        XCTAssertEqual(activities[1].sportType, "Run", "Falls back to the legacy type")
        XCTAssertTrue(activities[1].isFromKinetix)
        XCTAssertTrue(activities[1].routeCoordinates.isEmpty)
        XCTAssertEqual(activities[2].category, .cycling)
    }

    func testPolylineDecoding() {
        // Google's documented example.
        let points = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 1e-6)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 1e-6)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 1e-6)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 1e-6)
        XCTAssertTrue(Polyline.decode("").isEmpty)
    }
}
