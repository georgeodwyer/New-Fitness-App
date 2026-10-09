import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class AccountServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
        SampleData.seed(into: context)
        SampleData.seedHistory(into: context)
    }

    func testExportContainsEverything() throws {
        let export = AccountService.makeExport(in: context)
        XCTAssertEqual(export.profile, SampleData.profile)
        XCTAssertFalse(export.plannedSessions.isEmpty)
        XCTAssertFalse(export.runs.isEmpty)
        XCTAssertFalse(export.strengthWorkouts.isEmpty)
        XCTAssertFalse(export.personalRecords.isEmpty)

        let url = try AccountService.writeExportFile(in: context)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertNotNil(json?["plannedSessions"])
        XCTAssertEqual(json?["app"] as? String, "Kinetix")
    }

    func testDeleteEverythingLeavesNothing() throws {
        AccountService.deleteEverything(in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<UserProfileModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlannedSessionModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<RunLogModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StrengthLogModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersonalRecordModel>()).isEmpty)
    }

    func testChangingUnitsUpdatesRunSummaries() throws {
        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfileModel>()).first)
        AccountService.changeUnits(to: .imperial, profile: profile, in: context)
        XCTAssertEqual(profile.units, .imperial)
        let runs = try context.fetch(FetchDescriptor<PlannedSessionModel>()).filter { $0.kind.discipline == .run && $0.estimatedDistanceMeters != nil }
        XCTAssertFalse(runs.isEmpty)
        XCTAssertTrue(runs.allSatisfy { $0.summary.hasSuffix(" mi") }, runs.map(\.summary).joined(separator: "; "))
    }
}
