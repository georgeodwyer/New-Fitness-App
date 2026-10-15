import XCTest
@testable import TrainingEngine

final class RunAnalysisTests: XCTestCase {
    /// A straight run north: one point every `step` metres at the given paces (s/km) per km.
    private func route(kmPaces: [Double], step: Double = 50) -> [RoutePoint] {
        var points = [RoutePoint(latitude: 51.5, longitude: -0.12, elapsed: 0)]
        var elapsed = 0.0, north = 0.0
        for pace in kmPaces {
            for _ in 0..<Int(1000 / step) {
                north += step
                elapsed += pace * step / 1000
                let (lat, lon) = Geo.offset(latitude: 51.5, longitude: -0.12, northMeters: north, eastMeters: 0)
                points.append(RoutePoint(latitude: lat, longitude: lon, elapsed: elapsed))
            }
        }
        return points
    }

    func testBestKilometreFindsTheFastestStretch() throws {
        // 6 km so the 5K fits comfortably (GPS maths makes "exactly 5 km" a hair short).
        let points = route(kmPaces: [330, 330, 270, 330, 330, 330])
        let best = try XCTUnwrap(RunAnalysis.bestTime(over: 1000, route: points))
        XCTAssertEqual(best, 270, accuracy: 1.5)
        // Best 5K includes the fast kilometre.
        XCTAssertEqual(try XCTUnwrap(RunAnalysis.bestTime(over: 5000, route: points)), 1590, accuracy: 3)
    }

    func testBestEffortStraddlingTwoKilometres() throws {
        // 500 m fast at the end of km 2 and start of km 3 can't be found by splits alone.
        var paces = [Double](repeating: 330, count: 4)
        paces[1] = 300; paces[2] = 300
        let best = try XCTUnwrap(RunAnalysis.bestTime(over: 2000, route: route(kmPaces: paces)))
        XCTAssertEqual(best, 600, accuracy: 2)
    }

    func testDistancesLongerThanTheRunAreMissing() {
        let efforts = RunAnalysis.bestEfforts(route: route(kmPaces: [300, 300, 300]))
        XCTAssertNotNil(efforts[.oneKilometre])
        XCTAssertNotNil(efforts[.oneMile])
        XCTAssertNil(efforts[.fiveK])
        XCTAssertNil(RunAnalysis.bestTime(over: 1000, route: []))
    }

    func testPrivacyTrimDropsStartAndFinish() {
        let points = route(kmPaces: [300, 300]) // 2 km, a point every 50 m
        let trimmed = RunAnalysis.privacyTrimmed(points, meters: 200)
        let cumulative = RunAnalysis.cumulativeDistances(points)
        // About 4 points (200 m) gone from each end (GPS rounding can shift one either way).
        XCTAssertTrue((points.count - 10...points.count - 7).contains(trimmed.count), "\(trimmed.count) of \(points.count)")
        XCTAssertEqual(trimmed.first, points[cumulative.firstIndex { $0 >= 200 }!])
        // A very short run keeps its middle third rather than vanishing.
        let short = Array(points.prefix(7)) // 300 m
        XCTAssertGreaterThanOrEqual(RunAnalysis.privacyTrimmed(short, meters: 200).count, 2)
    }

    func testPaceSeriesIsSmoothedAndInOrder() {
        let series = RunAnalysis.paceSeries(route: route(kmPaces: [300, 360]), windowSeconds: 60)
        XCTAssertFalse(series.isEmpty)
        XCTAssertEqual(series.map(\.elapsed), series.map(\.elapsed).sorted())
        XCTAssertEqual(series.first?.value ?? 0, 300, accuracy: 3)
        XCTAssertEqual(series.last?.value ?? 0, 360, accuracy: 3)
    }

    func testHeartRateSeriesAveragesBuckets() {
        let samples = (0..<12).map { HeartRateSample(elapsed: Double($0 * 5), bpm: Double(120 + $0)) }
        let series = RunAnalysis.heartRateSeries(samples, windowSeconds: 30)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].value, 122.5, accuracy: 0.01)
    }
}

final class TrainingHistoryTests: XCTestCase {
    private let calendar = Calendar.kinetix
    private var wednesday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))! }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: wednesday)! }

    func testPeriodTotals() {
        let entries = [
            RunHistoryEntry(date: day(-1), distanceMeters: 8000, durationSeconds: 2400),   // this week
            RunHistoryEntry(date: day(-5), distanceMeters: 10000, durationSeconds: 3000),  // last week, same month
            RunHistoryEntry(date: day(-40), distanceMeters: 5000, durationSeconds: 1500)   // earlier this year
        ]
        let totals = TrainingHistory.periodTotals(entries, today: wednesday, calendar: calendar)
        XCTAssertEqual(totals.week, RunTotals(distanceMeters: 8000, durationSeconds: 2400, count: 1))
        XCTAssertEqual(totals.month.count, 2)
        XCTAssertEqual(totals.year.distanceMeters, 23000)
        XCTAssertEqual(totals.week.averagePace?.secondsPerKm ?? 0, 300, accuracy: 0.01)
    }

    func testWeeklySeriesIsOldestFirstWithPlannedValues() {
        let monday = calendar.startOfISOWeek(for: wednesday)
        let values = [(date: day(0), value: 5000.0), (date: day(-7), value: 12000.0), (date: day(-8), value: 3000.0)]
        let weeks = TrainingHistory.weekly(values, weeks: 3, today: wednesday, calendar: calendar, planned: [monday: 20000])
        XCTAssertEqual(weeks.map(\.actual), [0, 15000, 5000])
        XCTAssertEqual(weeks.last?.planned, 20000)
        XCTAssertNil(weeks.first?.planned)
        XCTAssertEqual(weeks.last?.weekStart, monday)
    }
}
