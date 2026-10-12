import XCTest
@testable import TrainingEngine

final class BalanceRulesTests: XCTestCase {
    func testBundledFileMatchesTheDesignedDefaults() throws {
        // If you edit balance_rules.json on purpose, update `BalanceRules.defaults` to match.
        XCTAssertEqual(try BalanceRules.bundled(), BalanceRules.defaults)
        XCTAssertEqual(BalanceRules.current, BalanceRules.defaults)
        XCTAssertEqual(LoadStatus.optimalRange, 0.8...1.3)
        XCTAssertEqual(LoadModel.minimumHistoryDays, 14)
    }

    func testValidationRejectsBrokenValues() {
        var rules = BalanceRules.defaults
        rules.load.optimalRatioLow = 1.5
        XCTAssertThrowsError(try rules.validate())
        rules = .defaults
        rules.rebalancing.highLoadEasyRunFactor = 1.2
        XCTAssertThrowsError(try rules.validate())
        rules = .defaults
        rules.recovery.verySoreAtOrAbove = 9
        XCTAssertThrowsError(try rules.validate())
        XCTAssertNoThrow(try BalanceRules.defaults.validate())
    }

    func testRecoveryThresholdsComeFromRules() {
        let checkIn = RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3) // readiness 0.5
        var rules = BalanceRules.defaults.recovery
        XCTAssertFalse(checkIn.isPoor(rules: rules))
        rules.poorReadinessBelow = 0.55
        XCTAssertTrue(checkIn.isPoor(rules: rules))
        rules = BalanceRules.defaults.recovery
        rules.verySoreAtOrAbove = 3
        XCTAssertTrue(checkIn.isPoor(rules: rules))
    }
}

final class PlanChangeDiffTests: XCTestCase {
    private let monday = Calendar.kinetix.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7))!

    private func snapshot(day: Int = 0, kind: SessionKind = .run(.tempo), title: String = "Tempo run", minutes: Double = 50,
                          effort: Double = 7.5, distance: Double? = 9000, status: SessionStatus = .planned) -> SessionSnapshot {
        SessionSnapshot(date: Calendar.kinetix.date(byAdding: .day, value: day, to: monday)!, slot: .morning, kind: kind, title: title,
                        summary: "", durationMinutes: minutes, effort: effort, status: status, distanceMeters: distance)
    }

    func testEasedTempoShowsSessionDurationDistanceAndIntensity() {
        let changes = PlanChangeDiff.changes(from: snapshot(),
                                             to: snapshot(kind: .run(.easy), title: "Easy run", minutes: 40, effort: 4, distance: 7000),
                                             units: .metric)
        XCTAssertEqual(changes.map(\.field), [.session, .duration, .distance, .intensity])
        XCTAssertEqual(changes.first { $0.field == .duration }?.before, "50 min")
        XCTAssertEqual(changes.first { $0.field == .duration }?.after, "40 min")
        XCTAssertEqual(changes.first { $0.field == .distance }?.after, "7.0 km")
        XCTAssertEqual(changes.first { $0.field == .intensity }?.before, "Hard")
        XCTAssertEqual(changes.first { $0.field == .intensity }?.after, "Easy")
    }

    func testMovedSessionShowsOnlyTheDay() {
        let changes = PlanChangeDiff.changes(from: snapshot(day: 1), to: snapshot(day: 3), units: .metric)
        XCTAssertEqual(changes.map(\.field), [.day])
    }

    func testSkippedSessionShowsStatus() {
        let changes = PlanChangeDiff.changes(from: snapshot(), to: snapshot(status: .skipped), units: .imperial)
        XCTAssertEqual(changes.map(\.field), [.status])
        XCTAssertEqual(changes.first?.after, "Skipped")
    }

    func testSnapshotFromWeekSessionCountsSets() {
        let prescription = StrengthPrescription(exercises: [
            ExercisePrescription(exerciseId: "squat", name: "Squat", role: .main, sets: 3, repRange: RepRange(5, 5), weightKg: 100, restSeconds: 180),
            ExercisePrescription(exerciseId: "lunge", name: "Lunge", role: .accessory, sets: 2, repRange: RepRange(8, 10), weightKg: 20, restSeconds: 90)
        ])
        let session = WeekSession(id: UUID(), date: monday, slot: .evening, kind: .strength(.lower), isKey: false, title: "Lower body",
                                  durationMinutes: 55, effort: 7, strength: prescription)
        let snap = SessionSnapshot(session, zones: nil)
        XCTAssertEqual(snap.sets, 5)
        XCTAssertNil(snap.distanceMeters)
    }
}
