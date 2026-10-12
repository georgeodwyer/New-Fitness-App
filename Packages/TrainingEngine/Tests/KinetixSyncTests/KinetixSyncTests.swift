import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import KinetixSync

/// Records requests and replies with queued responses.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { var status: Int; var body: String }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        let reply = replies.isEmpty ? Reply(status: 500, body: "{}") : replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }
}

final class KinetixSyncTests: XCTestCase {
    private let config = SupabaseConfig(url: URL(string: "https://abc.supabase.co")!, anonKey: "anon-key")
    private let userId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func tokenJSON(access: String = "access-1", refresh: String = "refresh-1", expiresIn: Int = 3600) -> String {
        #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":\#(expiresIn),"user":{"id":"\#(userId.uuidString)","email":"a@b.com"}}"#
    }

    private func validSession(expires: Date = Date().addingTimeInterval(3600)) -> AuthSession {
        AuthSession(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: expires, userId: userId, email: "a@b.com")
    }

    func testConfigFromInfo() {
        XCTAssertNotNil(SupabaseConfig(info: ["SupabaseURL": "https://abc.supabase.co", "SupabaseAnonKey": "key"]))
        XCTAssertNil(SupabaseConfig(info: ["SupabaseURL": "", "SupabaseAnonKey": ""]))
        XCTAssertNil(SupabaseConfig(info: ["SupabaseURL": "https://your-project-ref.supabase.co", "SupabaseAnonKey": "key"]))
        XCTAssertNil(SupabaseConfig(info: nil))
    }

    func testSignInStoresSessionAndSendsHeaders() async throws {
        let transport = StubTransport([.init(status: 200, body: tokenJSON())])
        let client = SupabaseClient(config: config, transport: transport)
        let session = try await client.signIn(email: "a@b.com", password: "secret")
        XCTAssertEqual(session.userId, userId)
        XCTAssertEqual(session.email, "a@b.com")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/auth/v1/token?grant_type=password")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
        XCTAssertEqual(body?["email"], "a@b.com")
        let stored = await client.session
        XCTAssertEqual(stored, session)
    }

    func testSignUpNeedingConfirmation() async throws {
        let transport = StubTransport([.init(status: 200, body: #"{"id":"\#(userId.uuidString)","email":"a@b.com"}"#)])
        let client = SupabaseClient(config: config, transport: transport)
        let result = try await client.signUp(email: "a@b.com", password: "secret12")
        XCTAssertEqual(result, .confirmationRequired(email: "a@b.com"))
    }

    func testServerErrorMessageIsSurfaced() async {
        let transport = StubTransport([.init(status: 400, body: #"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#)])
        let client = SupabaseClient(config: config, transport: transport)
        do {
            _ = try await client.signIn(email: "a@b.com", password: "wrong")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid login credentials")
        }
    }

    func testAppleSignInSendsIdTokenAndNonce() async throws {
        let transport = StubTransport([.init(status: 200, body: tokenJSON())])
        let client = SupabaseClient(config: config, transport: transport)
        _ = try await client.signInWithApple(idToken: "apple-jwt", nonce: "raw-nonce")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertTrue(request.url!.absoluteString.hasSuffix("grant_type=id_token"))
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String]
        XCTAssertEqual(body, ["provider": "apple", "id_token": "apple-jwt", "nonce": "raw-nonce"])
    }

    func testPushUpsertsWithBearerToken() async throws {
        let transport = StubTransport([.init(status: 201, body: "")])
        let client = SupabaseClient(config: config, transport: transport, session: validSession())
        let record = SyncRecord(id: UUID(), type: "plannedSession", updatedAt: Date(timeIntervalSince1970: 1_000_000),
                                deletedAt: nil, payload: .object(["title": .string("Tempo Run")]))
        try await client.push([record])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://abc.supabase.co/rest/v1/records?on_conflict=id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let rows = try JSONSerialization.jsonObject(with: request.httpBody!) as? [[String: Any]]
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(rows?.first?["type"] as? String, "plannedSession")
        XCTAssertTrue(rows?.first?.keys.contains("deleted_at") ?? false, "deleted_at is always sent")
        XCTAssertNil(rows?.first?["user_id"], "The server fills in the user")
    }

    func testPushBatches() async throws {
        let transport = StubTransport(Array(repeating: .init(status: 201, body: ""), count: 3))
        let client = SupabaseClient(config: config, transport: transport, session: validSession())
        let records = (0..<450).map { _ in SyncRecord(id: UUID(), type: "t", updatedAt: Date(), deletedAt: nil, payload: .null) }
        try await client.push(records)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testPullParsesPostgresTimestampsAndAdvancesCursor() async throws {
        let id = UUID()
        let page = #"[{"id":"\#(id.uuidString)","type":"runLog","updated_at":"2026-10-12T09:30:00.123456+00:00","deleted_at":null,"payload":{"distance":5000},"server_updated_at":"2026-10-12T09:31:00.654321+00:00"}]"#
        let transport = StubTransport([.init(status: 200, body: page)])
        let client = SupabaseClient(config: config, transport: transport, session: validSession())
        let result = try await client.pull(after: "2026-10-01T00:00:00+00:00")
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].id, id)
        XCTAssertEqual(result.records[0].payload, .object(["distance": .number(5000)]))
        XCTAssertEqual(result.cursor, "2026-10-12T09:31:00.654321+00:00")
        XCTAssertEqual(result.records[0].updatedAt.timeIntervalSince1970, SyncCoding.parseDate("2026-10-12T09:30:00.123Z")!.timeIntervalSince1970, accuracy: 0.01)
        let url = transport.requests[0].url!.absoluteString
        XCTAssertTrue(url.contains("server_updated_at=gt.2026-10-01T00:00:00%2B00:00"), url)
    }

    func testExpiredTokenIsRefreshedAndRequestRetried() async throws {
        let transport = StubTransport([
            .init(status: 401, body: #"{"message":"JWT expired"}"#),
            .init(status: 200, body: tokenJSON(access: "access-2", refresh: "refresh-2")),
            .init(status: 200, body: "[]")
        ])
        let client = SupabaseClient(config: config, transport: transport, session: validSession())
        _ = try await client.pull(after: nil)
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.requests[1].url!.absoluteString.hasSuffix("grant_type=refresh_token"))
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer access-2")
    }

    func testSessionNearExpiryRefreshesFirst() async throws {
        let transport = StubTransport([
            .init(status: 200, body: tokenJSON(access: "access-2")),
            .init(status: 200, body: "[]")
        ])
        let client = SupabaseClient(config: config, transport: transport, session: validSession(expires: Date().addingTimeInterval(10)))
        _ = try await client.pull(after: nil)
        XCTAssertTrue(transport.requests[0].url!.absoluteString.hasSuffix("grant_type=refresh_token"))
    }

    func testDeleteAccountCallsFunctionAndSignsOut() async throws {
        let transport = StubTransport([.init(status: 204, body: "")])
        let client = SupabaseClient(config: config, transport: transport, session: validSession())
        try await client.deleteAccount()
        XCTAssertTrue(transport.requests[0].url!.absoluteString.hasSuffix("rest/v1/rpc/delete_my_account"))
        let session = await client.session
        XCTAssertNil(session)
    }

    func testNotSignedIn() async {
        let client = SupabaseClient(config: config, transport: StubTransport([]))
        do {
            _ = try await client.pull(after: nil)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SupabaseError, .notSignedIn)
        }
    }

    func testLastWriteWins() {
        let remote = SyncRecord(id: UUID(), type: "t", updatedAt: Date(timeIntervalSince1970: 200), deletedAt: nil, payload: .null)
        XCTAssertEqual(SyncMerge.decide(localUpdatedAt: nil, remote: remote), .applyRemote)
        XCTAssertEqual(SyncMerge.decide(localUpdatedAt: Date(timeIntervalSince1970: 100), remote: remote), .applyRemote)
        XCTAssertEqual(SyncMerge.decide(localUpdatedAt: Date(timeIntervalSince1970: 200), remote: remote), .keepLocal)
        XCTAssertEqual(SyncMerge.decide(localUpdatedAt: Date(timeIntervalSince1970: 300), remote: remote), .keepLocal)
    }

    func testJSONValueRoundTrip() throws {
        struct Sample: Codable, Equatable { var name: String; var when: Date; var reps: [Int]; var note: String? }
        let sample = Sample(name: "Squat", when: Date(timeIntervalSince1970: 1_700_000_000.5), reps: [8, 8, 7], note: nil)
        let value = try JSONValue.from(sample)
        XCTAssertEqual(try value.decode(Sample.self), sample)
    }
}
