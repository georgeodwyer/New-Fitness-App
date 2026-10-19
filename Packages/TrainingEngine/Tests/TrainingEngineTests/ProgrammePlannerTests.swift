import XCTest
@testable import TrainingEngine

/// The coach's half marathon (programmes.json), sized for three runners.
final class ProgrammePlannerTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let monday = TestSupport.monday
    private var generator: PlanGenerator { PlanGenerator(templates: TestSupport.bundledTemplates, calendar: calendar) }
    private var programme: Programme { TestSupport.bundledTemplates.programmes.programme(for: .halfMarathon)! }

    /// Race on the Sunday of the 12th week.
    private var raceDay: Date { calendar.date(byAdding: .day, value: 11 * 7 + 6, to: monday)! }

    private struct Runner {
        var name: String
        var level: ExperienceLevel
        var weeklyKm: Double
        var longestKm: Double
        var fiveK: Double
    }

    private let runners = [
        Runner(name: "15 km/week", level: .beginner, weeklyKm: 15, longestKm: 6, fiveK: 30 * 60),
        Runner(name: "30 km/week", level: .intermediate, weeklyKm: 30, longestKm: 12, fiveK: 24 * 60),
        Runner(name: "50 km/week", level: .advanced, weeklyKm: 50, longestKm: 18, fiveK: 20 * 60),
    ]

    private func profile(_ runner: Runner, days: [Weekday] = [.monday, .tuesday, .thursday, .saturday, .sunday], doubles: Int = 1,
                         event: Date? = nil) -> AthleteProfile {
        var profile = TestSupport.profile(running: runner.level, goal: .halfMarathon, event: event, days: days, doubles: doubles,
                                          race: RaceResult(distanceMeters: 5000, timeSeconds: runner.fiveK))
        profile.weeklyRunMeters = runner.weeklyKm * 1000
        profile.longestRecentRunMeters = runner.longestKm * 1000
        return profile
    }

    private func plan(_ profile: AthleteProfile) -> (outline: PlanOutline, weeks: [GeneratedWeek]) {
        let outline = generator.makeOutline(for: profile, startingOn: monday)
        let weeks = outline.weeks.indices.compactMap { generator.generateWeek($0, outline: outline, profile: profile) }
        return (outline, weeks)
    }

    private func runs(_ week: GeneratedWeek) -> [GeneratedSession] {
        week.sessions.filter { $0.kind.discipline == .run }
    }

    // MARK: Loading

    func testHalfMarathonLoads() {
        XCTAssertEqual(programme.weeks.count, 12)
        XCTAssertEqual(programme.sessions.count, 48)
        XCTAssertTrue(programme.sessions.allSatisfy { !$0.parts.isEmpty })
        XCTAssertEqual(programme.sessions.filter(\.isRace).count, 1)
        // Goals without a programme keep the rule-based planner.
        XCTAssertNil(TestSupport.bundledTemplates.programmes.programme(for: .buildMuscle))
    }

    // MARK: Outline

    func testStartVolumeStaysWithinTheRules() {
        let rules = TestSupport.bundledTemplates.programmes
        var beginner = profile(runners[0])
        beginner.weeklyRunMeters = 50000
        XCTAssertEqual(ProgrammePlanner.startVolume(profile: beginner, programme: programme, rules: rules.rules(for: .beginner)), 30000)
        beginner.weeklyRunMeters = nil
        XCTAssertEqual(ProgrammePlanner.startVolume(profile: beginner, programme: programme, rules: rules.rules(for: .beginner)), 8000)
        var advanced = profile(runners[2])
        advanced.weeklyRunMeters = 10000
        XCTAssertEqual(ProgrammePlanner.startVolume(profile: advanced, programme: programme, rules: rules.rules(for: .advanced)), 25000)
    }

    func testVolumesFollowTheProgramme() {
        let outline = generator.makeOutline(for: profile(runners[1]), startingOn: monday)
        XCTAssertEqual(outline.programmeGoal, .halfMarathon)
        XCTAssertEqual(outline.weeks.count, 13, "12 weeks and a recovery week")
        let km = outline.weeks.map { ($0.runVolumeMeters / 100).rounded() / 10 }
        // 100%, 105%, 110%, deload 90%, then 115%: not cut, because it's measured against week 3.
        XCTAssertEqual(Array(km.prefix(5)), [30, 31.5, 33, 27, 34.5])
        XCTAssertEqual(km[8], 39) // peak, 130%
        XCTAssertEqual(km[11], 16.5) // race week, 55% (not counting the race)
        XCTAssertTrue(outline.weeks[3].isRecoveryWeek)
        XCTAssertEqual(outline.weeks.last?.isPostProgrammeRecovery, true)
    }

    func testPlanLinesUpWithRaceDay() {
        let runner = runners[1]
        let onTime = generator.makeOutline(for: profile(runner, event: raceDay), startingOn: monday)
        XCTAssertEqual(onTime.weeks.first?.programmeWeek, 1)
        XCTAssertEqual(onTime.weeks[11].programmeWeek, 12)

        // Race in 8 weeks: start at programme week 5.
        let soon = calendar.date(byAdding: .day, value: 7 * 7 + 6, to: monday)!
        let short = generator.makeOutline(for: profile(runner, event: soon), startingOn: monday)
        XCTAssertEqual(short.weeks.first?.programmeWeek, 5)
        XCTAssertEqual(short.weeks[7].programmeWeek, 12)
        // Jumping in later still ramps up gently from the starting volume.
        XCTAssertLessThanOrEqual(short.weeks[0].runVolumeMeters, 30000 * 1.1 + 1)

        // Race in 16 weeks: four lead-in weeks first.
        let later = calendar.date(byAdding: .day, value: 15 * 7 + 6, to: monday)!
        let long = generator.makeOutline(for: profile(runner, event: later), startingOn: monday)
        XCTAssertEqual(long.weeks[4].programmeWeek, 1)
        XCTAssertEqual(long.weeks[15].programmeWeek, 12)
    }

    func testNextCycleStartsFromRecentRunning() {
        let runner = profile(runners[1])
        let outline = generator.makeOutline(for: runner, startingOn: monday)
        let next = try! XCTUnwrap(generator.nextCycle(of: outline, profile: runner, recentWeeklyRunMeters: 40000))
        XCTAssertEqual(next.weeks.count, 26)
        XCTAssertEqual(next.weeks[13].programmeWeek, 1)
        XCTAssertEqual(next.weeks[13].programmeCycle, 2)
        XCTAssertEqual(next.weeks[13].index, 13)
        // Back up gently from the taper and recovery weeks.
        XCTAssertLessThanOrEqual(next.weeks[13].runVolumeMeters, outline.weeks.suffix(3).map(\.runVolumeMeters).max()! * 1.1 + 1)
    }

    // MARK: Weeks

    func testEveryWeekFitsTheRunner() {
        for runner in runners {
            let (outline, weeks) = plan(profile(runner, event: raceDay))
            XCTAssertEqual(weeks.count, outline.weeks.count)
            let rules = TestSupport.bundledTemplates.programmes.rules(for: runner.level)
            for (week, target) in zip(weeks, outline.weeks) {
                let label = "\(runner.name) week \(target.index + 1)"
                XCTAssertTrue(week.sessions.allSatisfy { !$0.isKey }, label)
                let weekRuns = runs(week)
                XCTAssertFalse(weekRuns.isEmpty, label)
                for run in weekRuns where run.title != "Race day" {
                    XCTAssertLessThanOrEqual(run.estimatedDistanceMeters ?? 0, min(22000, rules.longestRunMeters) + 600, "\(label): \(run.title)")
                    XCTAssertGreaterThanOrEqual(run.estimatedDistanceMeters ?? 0, rules.shortestRunMeters - 600, "\(label): \(run.title)")
                }
                if target.programmeWeek != 12 {
                    let planned = weekRuns.compactMap(\.estimatedDistanceMeters).reduce(0, +)
                    XCTAssertEqual(planned, target.runVolumeMeters, accuracy: max(target.runVolumeMeters * 0.2, 3000), label)
                }
            }
        }
    }

    func testRepsScaleWithVolume() {
        // Week 3: 6 x 800 m @ I.
        func reps(_ runner: Runner) -> Int {
            let (_, weeks) = plan(profile(runner))
            let intervals = runs(weeks[2]).first { $0.title == "Intervals" }
            return intervals?.runStructure?.segments.filter { $0.kind == .work }.count ?? 0
        }
        XCTAssertLessThan(reps(runners[0]), 6)
        XCTAssertGreaterThanOrEqual(reps(runners[0]), 2)
        XCTAssertEqual(reps(runners[2]), 6)
    }

    func testRepSessionsHaveWarmUpAndCoolDown() {
        let (_, weeks) = plan(profile(runners[1]))
        let tempo = try! XCTUnwrap(runs(weeks[1]).first { $0.title == "Tempo run" })
        let segments = try! XCTUnwrap(tempo.runStructure?.segments)
        XCTAssertEqual(segments.first?.kind, .warmUp)
        XCTAssertEqual(segments.last?.kind, .coolDown)
        if case .distance(let meters) = segments.first?.length { XCTAssertGreaterThanOrEqual(meters, 1500) } else { XCTFail() }
    }

    func testEffortStepsAndHills() {
        let (_, weeks) = plan(profile(runners[1]))
        // Week 2 hills: timed reps with no pace target.
        let hills = try! XCTUnwrap(runs(weeks[1]).first { $0.title == "Hills" })
        let hillReps = hills.runStructure!.segments.filter { $0.kind == .work }
        XCTAssertFalse(hillReps.isEmpty)
        XCTAssertTrue(hillReps.allSatisfy { $0.targetPace == nil })
        // Week 4 fartlek "@ T effort": pace shown as a guide only.
        let fartlek = try! XCTUnwrap(runs(weeks[3]).first { $0.title == "Fartlek" })
        XCTAssertTrue(fartlek.runStructure!.segments.filter { $0.kind == .work }.allSatisfy { $0.paceIsGuide == true && $0.targetPace != nil })
    }

    func testShapeComesFromTheWorkout() {
        // Week 5 long run: "13 km E, final 3 km @ STEADY" → last ~23% steady, whatever the length.
        for runner in runners {
            let (_, weeks) = plan(profile(runner))
            let long = try! XCTUnwrap(runs(weeks[4]).first { $0.title == "Long run" })
            let segments = long.runStructure!.segments
            XCTAssertEqual(segments.count, 2, runner.name)
            let total = long.estimatedDistanceMeters ?? 1
            if case .distance(let steady) = segments[1].length {
                XCTAssertEqual(steady / total, 3.0 / 13.0, accuracy: 0.08, runner.name)
            } else {
                XCTFail(runner.name)
            }
        }
    }

    func testRaceIsOnRaceDay() {
        let (_, weeks) = plan(profile(runners[1], event: raceDay))
        let race = try! XCTUnwrap(runs(weeks[11]).first { $0.title == "Race day" })
        XCTAssertEqual(calendar.startOfDay(for: race.date), calendar.startOfDay(for: raceDay))
        XCTAssertEqual(race.estimatedDistanceMeters ?? 0, 21097.5, accuracy: 1)
        XCTAssertTrue(weeks[11].sessions.filter { $0.kind.discipline == .strength }.isEmpty, "No lifting in race week")
    }

    func testFewerRunDaysDropTheEasiestRuns() {
        let (_, weeks) = plan(profile(runners[1], days: [.monday, .wednesday, .saturday], doubles: 0))
        // Week 2 is hills, recovery, tempo and long: the recovery run goes.
        let titles = runs(weeks[1]).map(\.title)
        XCTAssertEqual(titles.count, 3)
        XCTAssertFalse(titles.contains("Recovery run"))
        XCTAssertTrue(titles.contains("Long run"))
    }

    func testMoreRunDaysAddEasyRuns() {
        // Six days plus a double day: room for five runs and two lifts.
        let days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday]
        let (_, weeks) = plan(profile(runners[2], days: days, doubles: 1))
        XCTAssertEqual(runs(weeks[0]).count, 5)
    }

    // MARK: Preview

    /// Prints every week for the three example runners as JSON lines starting "PREVIEW ",
    /// for the programme preview page.
    func testPrintPreview() {
        // Short lines, one per week and one per run, flushed as they go: very long stdout lines
        // can be cut short in CI logs.
        struct Segment: Encodable { var label: String; var length: String; var pace: String? }
        struct Run: Encodable { var runner: String; var week: Int; var date: String; var title: String; var km: Double; var summary: String; var segments: [Segment] }
        struct Week: Encodable {
            var runner: String; var week: Int; var programmeWeek: Int?; var phase: String; var deload: Bool
            var targetKm: Double; var plannedKm: Double; var lifts: Int; var notes: [String]
        }
        let encoder = JSONEncoder()
        func emit<T: Encodable>(_ prefix: String, _ value: T) {
            if let data = try? encoder.encode(value), let line = String(data: data, encoding: .utf8) {
                print(prefix + " " + line)
                fflush(stdout)
            }
        }
        let dayFormat = DateFormatter()
        dayFormat.calendar = calendar
        dayFormat.timeZone = calendar.timeZone
        dayFormat.dateFormat = "EEE d MMM"
        for runner in runners {
            let athlete = profile(runner, event: raceDay)
            let zones = PaceZones(profile: athlete)
            let (outline, weeks) = plan(athlete)
            for (week, target) in zip(weeks, outline.weeks) {
                emit("PREVIEW-WEEK", Week(runner: runner.name, week: target.index + 1, programmeWeek: target.programmeWeek,
                                          phase: target.isPostProgrammeRecovery == true ? "Recovery" : target.phase.displayName,
                                          deload: target.isRecoveryWeek, targetKm: (target.runVolumeMeters / 100).rounded() / 10,
                                          plannedKm: (week.plannedRunMeters / 100).rounded() / 10,
                                          lifts: week.sessions.filter { $0.kind.discipline == .strength }.count, notes: week.notes))
                for run in runs(week) {
                    let segments = (run.runStructure?.segments ?? []).map { segment -> Segment in
                        let length: String
                        switch segment.length {
                        case .distance(let meters): length = meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters)) m"
                        case .duration(let seconds): length = seconds >= 60 ? String(format: "%g min", seconds / 60) : "\(Int(seconds)) s"
                        }
                        let pace = segment.targetPace.map {
                            Units.formatPace($0.fastest, units: .metric) + "–" + Units.formatPace($0.slowest, units: .metric) + "/km"
                                + (segment.paceIsGuide == true ? " (effort)" : "")
                        }
                        return Segment(label: segment.label ?? segment.kind.rawValue, length: length, pace: pace)
                    }
                    emit("PREVIEW-RUN", Run(runner: runner.name, week: target.index + 1, date: dayFormat.string(from: run.date), title: run.title,
                                            km: ((run.estimatedDistanceMeters ?? 0) / 100).rounded() / 10, summary: run.summary, segments: segments))
                }
            }
            // The runner's paces.
            let paces = [PaceZone.easy, .steady, .marathon, .halfMarathon, .threshold, .tenK, .fiveK, .interval, .repetition].map { zone -> String in
                let range = zones.range(for: zone)
                return "\"\(zone.rawValue)\": \"\(Units.formatPace(range.fastest, units: .metric))–\(Units.formatPace(range.slowest, units: .metric))\""
            }
            print("PREVIEW-PACES {\"runner\": \"\(runner.name)\", " + paces.joined(separator: ", ") + "}")
            fflush(stdout)
        }
    }
}
