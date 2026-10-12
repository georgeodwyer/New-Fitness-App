import XCTest
import SwiftData
import TrainingEngine
import KinetixSync
@testable import Kinetix

/// An in-memory stand-in for Supabase's `records` table, with the same
/// last-write-wins rule and server timestamps as supabase/schema.sql.
final class FakeSupabase: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [UUID: [String: Any]] = [:]
    private var clock = 0

    var count: Int { lock.lock(); defer { lock.unlock() }; return rows.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock(); defer { lock.unlock() }
        let url = request.url!
        let ok = { (status: Int, body: Data) in (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!) }
        guard url.path.hasSuffix("/rest/v1/records") else { return ok(404, Data()) }

        if request.httpMethod == "POST" {
            let uploads = try JSONSerialization.jsonObject(with: request.httpBody!) as! [[String: Any]]
            for upload in uploads {
                let id = UUID(uuidString: upload["id"] as! String)!
                let incoming = SyncCoding.parseDate(upload["updated_at"] as! String)!
                if let existing = rows[id], let stored = SyncCoding.parseDate(existing["updated_at"] as! String), incoming < stored {
                    continue // older write ignored
                }
                clock += 1
                var row = upload
                row["server_updated_at"] = String(format: "2026-01-01T00:00:00.%06d+00:00", clock)
                rows[id] = row
            }
            return ok(201, Data())
        }

        // GET with optional server_updated_at=gt.<cursor>
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let after = query.first { $0.name == "server_updated_at" }?.value.map { String($0.dropFirst(3)) }
        let selected = rows.values
            .filter { row in after.map { (row["server_updated_at"] as! String) > $0 } ?? true }
            .sorted { ($0["server_updated_at"] as! String) < ($1["server_updated_at"] as! String) }
        return ok(200, try JSONSerialization.data(withJSONObject: selected))
    }
}

@MainActor
final class SyncServiceTests: XCTestCase {
    private let userId = UUID()
    private let server = FakeSupabase()
    private var containers: [ModelContainer] = []

    private func device() throws -> (ModelContext, SupabaseClient, UserDefaults) {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        let session = AuthSession(accessToken: "t", refreshToken: "r", expiresAt: .now.addingTimeInterval(3600), userId: userId, email: "a@b.com")
        let client = SupabaseClient(config: SupabaseConfig(url: URL(string: "https://test.supabase.co")!, anonKey: "k"),
                                    transport: server, session: session)
        let defaults = UserDefaults(suiteName: "sync-test-\(UUID().uuidString)")!
        return (container.mainContext, client, defaults)
    }

    func testEverySyncedTypeRoundTripsThroughThePayload() throws {
        let (context, _, _) = try device()
        SampleData.seed(into: context)
        SampleData.seedHistory(into: context)
        context.insert(RecoveryCheckInModel(date: .now, sleep: 4, soreness: 2, energy: 5))
        context.insert(PlanChangeModel(summary: "Moved your tempo run."))
        try context.save()
        for type in SyncRegistry.types {
            try assertRoundTrip(type, in: context)
        }
    }

    private func assertRoundTrip<T: SyncableModel>(_ type: T.Type, in context: ModelContext) throws {
        guard let original = try context.fetch(FetchDescriptor<T>()).first else { return }
        let record = try original.syncRecord()
        let copy = T.makeForSync(id: UUID())
        context.insert(copy)
        try copy.apply(record, context: context)
        XCTAssertEqual(try copy.syncRecord().payload, record.payload, "\(T.syncType) payload changed in a round trip")
        XCTAssertFalse(copy.needsSync)
        context.delete(copy)
    }

    func testSecondDeviceDownloadsEverything() async throws {
        let (a, clientA, defaultsA) = try device()
        SampleData.seed(into: a)
        SampleData.seedHistory(into: a)
        try await SyncService.sync(context: a, client: clientA, userId: userId, defaults: defaultsA)
        XCTAssertGreaterThan(server.count, 20)
        XCTAssertTrue(try a.fetch(FetchDescriptor<PlannedSessionModel>()).allSatisfy { !$0.needsSync }, "Uploaded records are marked synced")

        let (b, clientB, defaultsB) = try device()
        try await SyncService.sync(context: b, client: clientB, userId: userId, defaults: defaultsB)
        let profile = try XCTUnwrap(b.fetch(FetchDescriptor<UserProfileModel>()).first)
        // Dates travel with millisecond precision, so compare the answers rather than the exact value.
        XCTAssertEqual(profile.profile.goal, SampleData.profile.goal)
        XCTAssertEqual(profile.profile.trainingDays, SampleData.profile.trainingDays)
        XCTAssertEqual(profile.profile.equipment, SampleData.profile.equipment)
        let sessionsA = try a.fetch(FetchDescriptor<PlannedSessionModel>()).count
        let sessionsB = try b.fetch(FetchDescriptor<PlannedSessionModel>())
        XCTAssertEqual(sessionsB.count, sessionsA)
        XCTAssertTrue(sessionsB.allSatisfy { $0.plan != nil }, "Sessions are re-linked to their plan")
        let sets = try b.fetch(FetchDescriptor<SetLogModel>())
        XCTAssertFalse(sets.isEmpty)
        XCTAssertTrue(sets.allSatisfy { $0.session != nil }, "Sets are re-linked to their workout")
    }

    func testEditsFlowBetweenDevicesAndNewestWins() async throws {
        let (a, clientA, defaultsA) = try device()
        SampleData.seed(into: a)
        try await SyncService.sync(context: a, client: clientA, userId: userId, defaults: defaultsA)
        let (b, clientB, defaultsB) = try device()
        try await SyncService.sync(context: b, client: clientB, userId: userId, defaults: defaultsB)

        // B skips a session (newer edit).
        let sessionB = try XCTUnwrap(b.fetch(FetchDescriptor<PlannedSessionModel>()).first)
        let id = sessionB.id
        sessionB.status = .skipped
        try await SyncService.sync(context: b, client: clientB, userId: userId, defaults: defaultsB)

        // A had edited the same session earlier (older timestamp) but not synced yet.
        let sessionA = try XCTUnwrap(a.fetch(FetchDescriptor<PlannedSessionModel>()).first { $0.id == id })
        sessionA.title = "Older edit"
        sessionA.updatedAt = sessionB.updatedAt.addingTimeInterval(-60)
        sessionA.needsSync = true
        try await SyncService.sync(context: a, client: clientA, userId: userId, defaults: defaultsA)

        XCTAssertEqual(sessionA.status, .skipped, "B's newer edit wins on A")
        XCTAssertNotEqual(sessionA.title, "Older edit")
    }

    func testDeletionsSync() async throws {
        let (a, clientA, defaultsA) = try device()
        SampleData.seed(into: a)
        try await SyncService.sync(context: a, client: clientA, userId: userId, defaults: defaultsA)
        let (b, clientB, defaultsB) = try device()
        try await SyncService.sync(context: b, client: clientB, userId: userId, defaults: defaultsB)

        let change = PlanChangeModel(summary: "Temporary")
        a.insert(change)
        try await SyncService.sync(context: a, client: clientA, userId: userId, defaults: defaultsA)
        change.softDelete()
        try await SyncService.sync(context: a, client: clientA, userId: userId, defaults: defaultsA)
        try await SyncService.sync(context: b, client: clientB, userId: userId, defaults: defaultsB)

        let onB = try XCTUnwrap(b.fetch(FetchDescriptor<PlanChangeModel>()).first { $0.id == change.id })
        XCTAssertTrue(onB.isSoftDeleted)
    }

    func testTwoProfilesReconcileToTheNewest() async throws {
        let (a, clientA, defaultsA) = try device()
        SampleData.seed(into: a)
        try await SyncService.sync(context: a, client: clientA, userId: userId, defaults: defaultsA)

        // B onboarded separately before signing in.
        let (b, clientB, defaultsB) = try device()
        var other = SampleData.profile
        other.goal = .buildStrength
        b.insert(UserProfileModel(profile: other))
        try await SyncService.sync(context: b, client: clientB, userId: userId, defaults: defaultsB)

        let live = try b.fetch(FetchDescriptor<UserProfileModel>()).filter { !$0.isSoftDeleted }
        XCTAssertEqual(live.count, 1)
    }
}
