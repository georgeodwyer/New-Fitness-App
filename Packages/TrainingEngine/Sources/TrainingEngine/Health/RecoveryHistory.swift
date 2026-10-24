import Foundation

/// Recovery for past days, worked out the same way as today's: each day's HRV, resting heart
/// rate and sleep against the 30 days before it, plus that day's score if one was logged.
public enum RecoveryHistory {
    /// One score per day (0–100) for the last `lastDays` days that have any reading.
    public static func days(hrv: [HealthDay], restingHeartRate: [HealthDay], sleep: [HealthDay],
                            checkIns: [Date: RecoveryCheckIn] = [:], lastDays: Int = 30,
                            endingOn end: Date, calendar: Calendar) -> [HealthDay] {
        let endDay = calendar.startOfDay(for: end)
        guard let startDay = calendar.date(byAdding: .day, value: -(lastDays - 1), to: endDay) else { return [] }

        func byDay(_ days: [HealthDay]) -> [Date: Double] {
            Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0.value) }, uniquingKeysWith: { _, last in last })
        }
        let hrvByDay = byDay(hrv), restingByDay = byDay(restingHeartRate), sleepByDay = byDay(sleep)
        let checkInByDay = Dictionary(checkIns.map { (calendar.startOfDay(for: $0.key), $0.value) }, uniquingKeysWith: { _, last in last })

        /// Values from the 30 days before `day`, oldest first.
        func before(_ day: Date, in values: [Date: Double]) -> [Double] {
            guard let from = calendar.date(byAdding: .day, value: -30, to: day) else { return [] }
            return values.filter { $0.key >= from && $0.key < day }.sorted { $0.key < $1.key }.map(\.value)
        }

        var result: [HealthDay] = []
        var day = startDay
        while day <= endDay {
            let hrvSignal = hrvByDay[day].flatMap { HRVSignal.assess(today: $0, history: before(day, in: hrvByDay)) }
            let restingSignal = restingByDay[day].flatMap { RestingHeartRateSignal.assess(today: $0, history: before(day, in: restingByDay)) }
            let sleepHours = sleepByDay[day]
            let usualNights = before(day, in: sleepByDay)
            let usualSleep = usualNights.count >= 5 ? HealthTrend.median(usualNights) : nil
            if let score = RecoveryScore.make(hrv: hrvSignal, restingHeartRate: restingSignal, sleepHours: sleepHours,
                                              usualSleepHours: usualSleep, checkIn: checkInByDay[day]) {
                result.append(HealthDay(date: day, value: score.score))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
