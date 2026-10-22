import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class BalanceServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7))!

    override func setUp() async throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
        UserDefaults.standard.removeObject(forKey: BalanceService.lastAutoAdjustKey)
        PlanService.createPlan(for: SampleData.profile, in: context, now: monday)
    }

    private func thisWeek() throws -> [PlannedSessionModel] {
        let next = Calendar.kinetix.date(byAdding: .day, value: 7, to: Calendar.kinetix.startOfDay(for: monday))!
        return try context.fetch(FetchDescriptor<PlannedSessionModel>(sortBy: [SortDescriptor(\.date)]))
            .filter { !$0.isSoftDeleted && $0.date < next }
    }

    func testSwapStrengthToReducedVolumeRecordsChange() throws {
        let lift = try XCTUnwrap(thisWeek().first { $0.strengthPrescription != nil })
        let originalSets = lift.strengthPrescription!.exercises.reduce(0) { $0 + $1.sets }
        let option = try XCTUnwrap(BalanceService.swapOptions(for: lift, profile: SampleData.profile, now: monday).first { $0.id == "reduced" })
        let explanations = BalanceService.swap(lift, to: option, profile: SampleData.profile, in: context, now: monday)

        XCTAssertEqual(lift.status, .swapped)
        XCTAssertLessThan(lift.strengthPrescription!.exercises.reduce(0) { $0 + $1.sets }, originalSets)
        XCTAssertEqual(explanations.count, 1)
        XCTAssertNotNil(lift.changeReason)
        let changes = try context.fetch(FetchDescriptor<PlanChangeModel>())
        XCTAssertTrue(changes.contains { $0.sessionId == lift.id })
    }

    func testSwapRunToCrossTrainingKeepsOriginalKind() throws {
        let run = try XCTUnwrap(thisWeek().first { $0.kind.discipline == .run })
        let originalKind = run.kind
        let option = try XCTUnwrap(BalanceService.swapOptions(for: run, profile: SampleData.profile, now: monday).first { $0.id == "crossTraining" })
        BalanceService.swap(run, to: option, profile: SampleData.profile, in: context, now: monday)
        XCTAssertEqual(run.kind, .crossTraining)
        XCTAssertEqual(StoredJSON.decode(SessionKind.self, from: run.originalKindData), originalKind)
        XCTAssertNil(run.runStructure)
    }

    func testChangesRecordBeforeAfterAndTriggers() throws {
        let run = try XCTUnwrap(thisWeek().first { $0.kind.discipline == .run })
        let originalTitle = run.title
        let option = try XCTUnwrap(BalanceService.swapOptions(for: run, profile: SampleData.profile, now: monday).first { $0.id == "crossTraining" })
        BalanceService.swap(run, to: option, profile: SampleData.profile, in: context, now: monday)
        let change = try XCTUnwrap(context.fetch(FetchDescriptor<PlanChangeModel>()).first { $0.sessionId == run.id })
        XCTAssertEqual(change.cause, .swapped)
        XCTAssertEqual(change.before?.title, originalTitle)
        XCTAssertEqual(change.after?.kind, .crossTraining)
        XCTAssertEqual(change.triggers.first?.label, "You chose")
        let fields = PlanChangeDiff.changes(from: try XCTUnwrap(change.before), to: try XCTUnwrap(change.after), units: .metric)
        XCTAssertTrue(fields.contains { $0.field == .session })
    }

    func testHighLoadChangeRecordsTheRatio() throws {
        BalanceService.autoAdjust(profile: SampleData.profile, status: .high, checkIn: nil, in: context, now: monday, force: true, ratio: 1.42)
        let changes = try context.fetch(FetchDescriptor<PlanChangeModel>()).filter { $0.cause == .highLoad }
        XCTAssertFalse(changes.isEmpty)
        XCTAssertEqual(changes.first?.triggers.first?.value, "1.42")
        XCTAssertNotNil(changes.first?.before)
    }

    func testPoorRecoveryTriggersIncludeCheckInAndRestingHeartRate() {
        let checkIn = RecoveryCheckIn(sleep: 2, soreness: 4, energy: 2, restingHeartRateElevated: true)
        let triggers = BalanceService.recoveryTriggers(checkIn, restingHeartRate: RestingHeartRateSignal(today: 60, baseline: 51))
        XCTAssertEqual(triggers.map(\.label), ["Your score", "Sleep", "Soreness", "Energy", "Resting HR"])
        XCTAssertEqual(triggers.last?.value, "+9 bpm")
        XCTAssertTrue(BalanceService.recoveryTriggers(RecoveryCheckIn(sleep: 5, soreness: 1, energy: 5), restingHeartRate: nil).isEmpty)
    }

    func testSkipNonKeySession() throws {
        let session = try XCTUnwrap(thisWeek().first { !$0.isKey })
        let explanations = BalanceService.skip(session, profile: SampleData.profile, in: context, now: monday)
        XCTAssertEqual(session.status, .skipped)
        XCTAssertFalse(explanations.isEmpty)
    }

    func testAutoAdjustRunsOncePerDay() throws {
        let first = BalanceService.autoAdjust(profile: SampleData.profile, status: .high, checkIn: nil, in: context, now: monday)
        let second = BalanceService.autoAdjust(profile: SampleData.profile, status: .high, checkIn: nil, in: context, now: monday)
        XCTAssertFalse(first.isEmpty, "A load spike eases something this week")
        XCTAssertTrue(second.isEmpty, "Doesn't adjust twice on the same day")
    }

    func testDashboardDataAdherenceAndLoad() throws {
        let sessions = try thisWeek()
        sessions.first?.status = .completed
        let run = RunLogModel(plannedSessionId: nil, startedAt: monday)
        run.isFinished = true
        run.load = 300
        run.distanceMeters = 8000
        context.insert(run)
        let data = DashboardService.make(sessions: sessions, runs: [run], lifts: [], checkIns: [], profile: SampleData.profile,
                                         now: monday.addingTimeInterval(3600 * 12))
        XCTAssertEqual(data.week.count, 7)
        XCTAssertEqual(data.adherence.completed, 1)
        XCTAssertEqual(data.actualRunMeters, 8000)
        XCTAssertEqual(data.load.running.acute, 300)
        XCTAssertGreaterThan(data.plannedRunMeters, 0)
        XCTAssertGreaterThan(data.plannedLiftVolumeKg, 0)
    }
}
