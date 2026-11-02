import XCTest
@testable import TrainingEngine

/// Prints a whole plan as lines starting "PLAN5K " (read from the CI log to check the logic).
final class PlanPrintoutTests: XCTestCase {
    func testPrintSub21FiveKPlan() {
        let calendar = TestSupport.calendar
        let monday = TestSupport.monday
        let generator = PlanGenerator(templates: TestSupport.bundledTemplates, calendar: calendar)
        let raceDay = calendar.date(byAdding: .day, value: 11 * 7 + 5, to: monday)! // Saturday of week 12
        // An intermediate runner: 5K in 22:30, about 30 km a week, longest run 12 km, going for sub-21.
        var profile = TestSupport.profile(running: .intermediate, goal: .faster5k, event: raceDay,
                                          days: [.monday, .tuesday, .thursday, .saturday, .sunday], doubles: 1,
                                          race: RaceResult(distanceMeters: 5000, timeSeconds: 22 * 60 + 30))
        profile.weeklyRunMeters = 30_000
        profile.longestRecentRunMeters = 12_000
        profile.goalTimeSeconds = 20 * 60 + 55
        profile.liftSessionsPerWeek = 2
        profile.splitCode = "runner2"

        let zones = PaceZones(profile: profile)
        let order: [PaceZone] = [.easy, .steady, .marathon, .halfMarathon, .threshold, .tenK, .fiveK, .interval, .repetition]
        for zone in order {
            let range = zones.range(for: zone)
            print("PLAN5K PACE \(zone.rawValue) \(Units.formatPace(range.fastest, units: .metric))-\(Units.formatPace(range.slowest, units: .metric))")
        }
        if let goal = zones.goalPaceRange {
            print("PLAN5K PACE goal \(Units.formatPace(goal.fastest, units: .metric))-\(Units.formatPace(goal.slowest, units: .metric))")
        }
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "EEE"
        let outline = generator.makeOutline(for: profile, startingOn: monday)
        // The race is run at the goal pace range, and race week isn't more running than planned.
        if let raceWeek = outline.weeks.indices.last(where: { outline.weeks[$0].startDate <= raceDay }),
           let week = generator.generateWeek(raceWeek, outline: outline, profile: profile),
           let race = week.sessions.first(where: { $0.title.lowercased().contains("race") || $0.plannedEffort >= 9 }) {
            XCTAssertEqual(race.runStructure?.segments.first(where: { $0.kind == .work })?.targetPace, zones.goalPaceRange)
            let total = week.sessions.compactMap(\.estimatedDistanceMeters).reduce(0, +)
            XCTAssertLessThanOrEqual(total, outline.weeks[raceWeek].runVolumeMeters * 1.15)
        }
        for index in outline.weeks.indices {
            let target = outline.weeks[index]
            guard let week = generator.generateWeek(index, outline: outline, profile: profile) else { continue }
            let runKm = week.sessions.compactMap(\.estimatedDistanceMeters).reduce(0, +) / 1000
            print("PLAN5K WEEK \(index + 1) | \(target.isRecoveryWeek ? "easier" : target.phase.displayName) | target \(String(format: "%.1f", target.runVolumeMeters / 1000)) km | planned \(String(format: "%.1f", runKm)) km | notes: \(week.notes.joined(separator: " / "))")
            for session in week.sessions {
                let day = format.string(from: session.date)
                if let structure = session.runStructure {
                    let parts = structure.segments.map { segment -> String in
                        let length: String
                        switch segment.length {
                        case .distance(let meters): length = meters >= 1000 ? String(format: "%.1fkm", meters / 1000) : "\(Int(meters))m"
                        case .duration(let seconds): length = seconds >= 60 ? "\(Int(seconds / 60))min\(Int(seconds) % 60 > 0 ? "\(Int(seconds) % 60)s" : "")" : "\(Int(seconds))s"
                        }
                        let pace = segment.targetPace.map { " @\(Units.formatPace($0.fastest, units: .metric))-\(Units.formatPace($0.slowest, units: .metric))" } ?? ""
                        return "\(segment.label ?? segment.kind.rawValue) \(length)\(pace)"
                    }
                    print("PLAN5K RUN \(index + 1) | \(day) \(session.slot.rawValue) | \(session.title) | \(String(format: "%.1f", (session.estimatedDistanceMeters ?? 0) / 1000)) km | \(session.summary) | \(parts.joined(separator: "; "))")
                } else if let strength = session.strength {
                    let exercises = strength.exercises.map { "\($0.name) \($0.sets)x\($0.repRange.lower)-\($0.repRange.upper)" }
                    print("PLAN5K GYM \(index + 1) | \(day) \(session.slot.rawValue) | \(session.title) | \(exercises.joined(separator: ", "))")
                } else {
                    print("PLAN5K OTHER \(index + 1) | \(day) | \(session.title) | \(session.summary)")
                }
                fflush(stdout)
            }
        }
    }
}
