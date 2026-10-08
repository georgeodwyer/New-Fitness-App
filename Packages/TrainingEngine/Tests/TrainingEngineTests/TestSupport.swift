import Foundation
@testable import TrainingEngine

enum TestSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 5 October 2026.
    static let monday = date(2026, 10, 5)

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static let templates: TemplateLibrary = {
        try! TemplateLibrary.bundled()
    }()

    static var generator: PlanGenerator { PlanGenerator(templates: templates, calendar: calendar) }

    static func profile(
        running: ExperienceLevel = .intermediate,
        lifting: ExperienceLevel = .intermediate,
        goal: TrainingGoal = .halfMarathon,
        event: Date? = nil,
        days: [Weekday] = [.monday, .tuesday, .wednesday, .friday, .sunday],
        doubles: Int = 1,
        equipment: Equipment = .fullGym,
        race: RaceResult? = RaceResult(distanceMeters: 5000, timeSeconds: 22 * 60),
        estimates: [LiftEstimate] = []
    ) -> AthleteProfile {
        AthleteProfile(
            runningExperience: running,
            recentRace: race,
            liftingExperience: lifting,
            liftEstimates: estimates,
            goal: goal,
            eventDate: event,
            trainingDays: days,
            doubleSessionDays: doubles,
            equipment: equipment
        )
    }

    /// Every non-empty subset of weekdays with at least `minCount` days.
    static func daySubsets(minCount: Int = 2) -> [[Weekday]] {
        (1..<(1 << 7)).compactMap { mask -> [Weekday]? in
            let days = Weekday.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            return days.count >= minCount ? days : nil
        }
    }
}
