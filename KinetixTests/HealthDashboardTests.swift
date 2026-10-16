import XCTest
import SwiftData
import TrainingEngine
@testable import Kinetix

@MainActor
final class HealthDashboardTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeContainer(inMemory: true)
        containers.append(container)
        return container.mainContext
    }

    func testLowHRVShowsInWhyItChanged() {
        let checkIn = RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3, hrvSuppressed: true)
        XCTAssertTrue(checkIn.isPoor)
        let triggers = BalanceService.recoveryTriggers(checkIn, restingHeartRate: nil, hrv: HRVSignal(today: 48, baseline: 60))
        let hrv = triggers.first { $0.label == "HRV" }
        XCTAssertEqual(hrv?.value, "-20%")
        XCTAssertEqual(hrv?.detail, "48 ms vs usual 60")
    }

    func testHRVSignalUsesTodaysReadingOnly() {
        let calendar = Calendar.kinetix
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let history = (1...10).map { HealthDay(date: calendar.date(byAdding: .day, value: -$0, to: today)!, value: 60) }.reversed()
        XCTAssertNil(HealthService.hrvSignal(from: Array(history), now: now), "No reading today")
        let withToday = Array(history) + [HealthDay(date: today, value: 45)]
        XCTAssertEqual(HealthService.hrvSignal(from: withToday, now: now)?.isSuppressed, true)
    }

    func testDashboardLayoutStoresAndSyncs() throws {
        let context = try makeContext()
        let settings = CoachingSettingsModel()
        context.insert(settings)
        XCTAssertEqual(settings.dashboardLayout, .default)
        XCTAssertNil(settings.dashboardLayoutData, "The default layout isn't stored")

        var layout = DashboardLayout.default
        layout.setHidden(.records, true)
        layout.move(fromOffsets: IndexSet(integer: DashboardCard.defaultOrder.firstIndex(of: .body)!), toOffset: 0)
        settings.dashboardLayout = layout
        try context.save()

        let record = try settings.syncRecord()
        let copy = CoachingSettingsModel.makeForSync(id: UUID())
        try copy.apply(record, context: context)
        XCTAssertEqual(copy.dashboardLayout.visibleCards.first, .body)
        XCTAssertTrue(copy.dashboardLayout.isHidden(.records))
    }

    func testSampleBodyDataForScreenshots() {
        let health = HealthService()
        health.loadSample()
        XCTAssertTrue(health.isConnected)
        XCTAssertEqual(health.trends.count, HealthMetric.allCases.count)
        XCTAssertNotNil(health.lastNightSleepHours)
        XCTAssertEqual(health.hrv?.isSuppressed, true)
    }
}
