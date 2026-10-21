import XCTest
@testable import TrainingEngine

final class StrainTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_760_000_000) // a fixed morning (08:53 UTC)

    func testZonesFromAge() {
        let zones = HeartRateZones.make(age: 40, recordedMax: nil)
        XCTAssertEqual(zones.maxHeartRate, 180)
        XCTAssertEqual(zones.maxSource, .age)
        XCTAssertEqual(zones.starts, [90, 108, 126, 144, 162])
        XCTAssertEqual(zones.zone(for: 80), 0)
        XCTAssertEqual(zones.zone(for: 130), 3)
        XCTAssertEqual(zones.zone(for: 175), 5)
        XCTAssertEqual(zones.range(of: 2), 108...125)
    }

    func testRecordedMaxRaisesZonesButIgnoresOneSpike() {
        XCTAssertEqual(HeartRateZones.recordedMax([186, 240, 179, 188]), 186)
        XCTAssertNil(HeartRateZones.recordedMax([200]))
        let zones = HeartRateZones.make(age: 40, recordedMax: 186)
        XCTAssertEqual(zones.maxHeartRate, 186)
        XCTAssertEqual(zones.maxSource, .recorded)
        // A lower recorded max doesn't pull the age estimate down.
        XCTAssertEqual(HeartRateZones.make(age: 40, recordedMax: 170).maxHeartRate, 180)
    }

    func testCustomZones() {
        let settings = HeartRateZoneSettings(maxHeartRate: 195, zoneStarts: [100, 120, 140, 160, 175])
        let zones = HeartRateZones.make(age: 40, recordedMax: 186, settings: settings)
        XCTAssertTrue(zones.isCustom)
        XCTAssertEqual(zones.maxSource, .custom)
        XCTAssertEqual(zones.maxHeartRate, 195)
        XCTAssertEqual(zones.zone(for: 150), 3)
        // Out-of-order starts fall back to the automatic zones.
        let bad = HeartRateZones.make(age: 40, recordedMax: nil, settings: HeartRateZoneSettings(zoneStarts: [100, 90, 140, 160, 175]))
        XCTAssertFalse(bad.isCustom)
    }

    func testStrainScale() {
        XCTAssertEqual(Strain.strain(load: 0), 0)
        XCTAssertEqual(Strain.strain(load: 1000), 21, accuracy: 0.001)
        XCTAssertEqual(Strain.strain(load: 5000), 21)
        // An easy hour (zone 2) lands around 10, a hard hour around 13.
        XCTAssertEqual(Strain.strain(load: 120), 9.6, accuracy: 0.3)
        XCTAssertEqual(Strain.strain(load: 240), 13.0, accuracy: 0.3)
        XCTAssertEqual(Strain.load(forStrain: Strain.strain(load: 300)), 300, accuracy: 0.01)
    }

    func testHeartRateAndEffortAgree() {
        let zones = HeartRateZones.make(age: 40, recordedMax: nil)
        // An hour at 115 bpm (zone 2), a sample every 5 s.
        let samples = stride(from: 0.0, through: 3600, by: 5).map { HeartRateSample(elapsed: $0, bpm: 115) }
        XCTAssertEqual(Strain.load(samples: samples, zones: zones), 120, accuracy: 0.5)
        XCTAssertEqual(Strain.load(averageHeartRate: 115, durationSeconds: 3600, zones: zones), 120)
        // The same hour logged as effort 4 without heart rate.
        XCTAssertEqual(Strain.load(durationSeconds: 3600, effort: 4), 120)
        // A gap (watch lost contact) counts as 15 s, not the whole gap.
        let gappy = [HeartRateSample(elapsed: 0, bpm: 115), HeartRateSample(elapsed: 600, bpm: 115), HeartRateSample(elapsed: 605, bpm: 115)]
        XCTAssertEqual(Strain.load(samples: gappy, zones: zones), (15.0 + 5) / 60 * 2, accuracy: 0.001)
        let minutes = Strain.minutesInZones(samples: samples, zones: zones)
        XCTAssertEqual(minutes[2], 60, accuracy: 0.1)
    }

    func testRecovery() {
        XCTAssertNil(RecoveryScore.make(hrv: nil, restingHeartRate: nil, sleepHours: nil, checkIn: nil))
        let good = RecoveryScore.make(hrv: HRVSignal(today: 66, baseline: 60), restingHeartRate: RestingHeartRateSignal(today: 50, baseline: 52),
                                      sleepHours: 8.2, checkIn: nil)
        XCTAssertEqual(good?.band, .high)
        let poor = RecoveryScore.make(hrv: HRVSignal(today: 45, baseline: 60), restingHeartRate: RestingHeartRateSignal(today: 60, baseline: 52),
                                      sleepHours: 5, checkIn: RecoveryCheckIn(sleep: 2, soreness: 4, energy: 2))
        XCTAssertEqual(poor?.band, .low)
        // Check-in alone still gives a score.
        let checkInOnly = RecoveryScore.make(hrv: nil, restingHeartRate: nil, sleepHours: nil, checkIn: RecoveryCheckIn(sleep: 3, soreness: 3, energy: 3))
        XCTAssertEqual(checkInOnly?.score, 50)
        XCTAssertEqual(checkInOnly?.parts.count, 1)
    }

    func testTargetFollowsPlanAndRecovery() {
        let hardDay = StrainTarget.make(plannedLoad: 240, everydayLoad: 25, usualDailyLoad: 100, recovery: nil)
        let restDay = StrainTarget.make(plannedLoad: 0, everydayLoad: 25, usualDailyLoad: 100, recovery: nil)
        XCTAssertGreaterThan(hardDay.middle, restDay.middle + 5)
        XCTAssertEqual(hardDay.high - hardDay.low, 3, accuracy: 0.001)
        let lowRecovery = RecoveryScore(score: 20, parts: [])
        let highRecovery = RecoveryScore(score: 85, parts: [])
        let eased = StrainTarget.make(plannedLoad: 240, everydayLoad: 25, usualDailyLoad: 100, recovery: lowRecovery)
        let pushed = StrainTarget.make(plannedLoad: 240, everydayLoad: 25, usualDailyLoad: 100, recovery: highRecovery)
        XCTAssertLessThan(eased.middle, hardDay.middle)
        XCTAssertGreaterThan(pushed.middle, hardDay.middle)
        XCTAssertTrue(eased.reason.contains("Recovery is low"))
    }

    func testLegsAfterLegDayAndLongRun() {
        let quiet = (1...20).map { day in
            StrainActivity(id: "run\(day)", date: now.addingTimeInterval(-Double(day) * 86_400 - 3600), source: .run,
                           name: "Easy", load: day % 2 == 0 ? 100 : 0, legsShare: 1)
        }
        XCTAssertNotEqual(LegsLoad.make(activities: quiet, now: now, calendar: calendar).status, .tired)
        let heavy = quiet + [
            StrainActivity(id: "legs", date: now.addingTimeInterval(-20 * 3600), source: .lift, name: "Legs", load: 200, legsShare: 0.9),
            StrainActivity(id: "long", date: now.addingTimeInterval(-3 * 3600), source: .run, name: "Long run", load: 300, legsShare: 1)
        ]
        let legs = LegsLoad.make(activities: heavy, now: now, calendar: calendar)
        XCTAssertEqual(legs.status, .tired)
        XCTAssertNotNil(legs.usual)
        // Upper-body work doesn't tire the legs.
        let upper = StrainActivity(id: "push", date: now, source: .lift, name: "Push", load: 200, legsShare: 0)
        XCTAssertEqual(LegsLoad.fatigue(at: now, activities: [upper]), 0)
        XCTAssertEqual(LegsLoad.make(activities: [], now: now, calendar: calendar).status, .fresh)
    }

    func testReportCountsStepsOutsideWorkouts() {
        let today = calendar.startOfDay(for: now)
        let run = StrainActivity(id: "r", date: today.addingTimeInterval(8 * 3600), source: .run, name: "Easy run", load: 120, legsShare: 1,
                                 steps: StrainActivity.steps(meters: 11_000, running: true))
        let report = StrainReport.make(activities: [run], steps: [HealthDay(date: today, value: 18_000)], plannedLoadToday: 120,
                                       recovery: nil, now: now, calendar: calendar)
        let everyday = report.today.activities.first { $0.source == .steps }
        XCTAssertEqual(everyday?.load ?? 0, Strain.load(steps: 8000), accuracy: 0.5)
        XCTAssertEqual(report.today.load, 120 + 24, accuracy: 0.5)
        XCTAssertEqual(report.days.count, 30)
        XCTAssertNil(report.weekVsUsual)
        XCTAssertTrue(report.target.contains(report.today.strain))
    }

    func testWeekVsUsual() {
        let today = calendar.startOfDay(for: now)
        let activities = (0..<28).map { day in
            StrainActivity(id: "\(day)", date: today.addingTimeInterval(-Double(day) * 86_400 + 3600), source: .run, name: "Run",
                           load: day < 7 ? 150 : 100, legsShare: 1)
        }
        let report = StrainReport.make(activities: activities, steps: [], plannedLoadToday: nil, recovery: nil, now: now, calendar: calendar)
        // 7 × 150 against (7 × 150 + 21 × 100) / 4.
        XCTAssertEqual(report.weekVsUsual ?? 0, 1050 / (3150.0 / 4), accuracy: 0.001)
    }
}
