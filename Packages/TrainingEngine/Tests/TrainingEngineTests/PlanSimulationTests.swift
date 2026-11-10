import XCTest
@testable import TrainingEngine

/// A walk-through of one plan, week by week, using the engine's own rules: what each week holds,
/// what the runner did (simulated), and what that changes for the next week and why. It prints a
/// report (`swift test --filter PlanSimulationTests`) and checks the plan stays sensible.
///
/// The runner: Faster 10K, intermediate, no race date, runs on four days and gym on five (Push,
/// Pull, Legs, Upper, Shoulders & arms), Friday off, plan started Monday 26 October 2026.
/// What happens to them (to show each way one week feeds the next):
/// - week 2 felt too easy (weekly check-in) → week 3's easy and long runs a little longer;
/// - week 6 is a bad week (poor sleep): a low-recovery day cuts Wednesday's session, lifts miss
///   reps, and the check-in says too much → week 7 a little lighter;
/// - from week 5 interval reps are run a little quicker than target → the app offers faster
///   paces, which they accept, and the rest of the plan is rebuilt with them;
/// - after the programme and its recovery week, the next time through starts from what they
///   actually ran.
final class PlanSimulationTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let templates = TestSupport.bundledTemplates
    private var generator: PlanGenerator { PlanGenerator(templates: templates, calendar: calendar) }
    private let start = TestSupport.date(2026, 10, 26)

    private var startingProfile: AthleteProfile {
        AthleteProfile(runningExperience: .intermediate, liftingExperience: .intermediate, goal: .faster10k,
                       trainingDays: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday], doubleSessionDays: 3,
                       equipment: .fullGym, weeklyRunMeters: 15000, longestRecentRunMeters: 4500,
                       liftSessionsPerWeek: 5, splitCode: "pplUpperArms", longRunDay: .sunday)
    }

    // MARK: The simulated lifter

    /// Strength as an estimated one-rep max per exercise, growing a little with each session.
    private struct Lifter {
        var oneRepMax: [String: Double] = [:]

        /// Sets done at `weight`: about one rep left in the tank on the first set, a little
        /// fewer reps on each set after. `offDay` is a bad day (poor sleep): about 7% weaker.
        mutating func sets(for exercise: ExercisePrescription, weight: Double, offDay: Bool) -> [SetResult] {
            let key = exercise.progressionKey
            if oneRepMax[key] == nil {
                // New to them: the starting weight leaves about four reps above the bottom of the range.
                oneRepMax[key] = weight * (1 + Double(exercise.repRange.lower + 4) / 30)
            }
            let strength = (oneRepMax[key] ?? weight) * (offDay ? 0.93 : 1)
            let capacity = 30 * (strength / max(weight, 1) - 1)
            return (0..<exercise.sets).map { set in
                let reps = Int((capacity - 1 - 0.7 * Double(set)).rounded(.down))
                return SetResult(weightKg: weight, reps: min(max(reps, 0), exercise.repRange.upper),
                                 rpe: min(10, 8 + Double(set) * 0.5), completed: true)
            }
        }

        /// Training makes them a little stronger (less so in a lighter week).
        mutating func trained(_ key: String, lightWeek: Bool) {
            oneRepMax[key] = (oneRepMax[key] ?? 0) * (lightWeek ? 1.002 : 1.006)
        }
    }

    // MARK: Report helpers

    private var report: [String] = []
    private func line(_ text: String = "") { report.append(text) }
    private func km(_ meters: Double) -> String { String(format: "%.1f km", meters / 1000) }
    private func kg(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value)) kg" : String(format: "%.1f kg", value)
    }
    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
    private func pace(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    // MARK: The walk-through

    func testWalkThroughThePlan() throws {
        var profile = startingProfile
        let programme = try XCTUnwrap(templates.programmes.programme(for: .faster10k))
        var outline = generator.makeOutline(for: profile, startingOn: start)
        let rules = templates.strength.progression ?? .standard

        var workingWeights: [String: Double] = [:]
        var states: [String: ProgressionState] = [:]
        var lifter = Lifter()
        var evidence: [FormEstimate.Evidence] = []
        var paceOfferTaken = false
        var actualWeekMeters: [Double] = []
        var mainLiftHistory: [String: [(week: Int, kg: Double)]] = [:]
        var pendingCheckIn: WeekFeel?
        var summaryRows: [String] = []
        var cycleExtended = false

        line("# Plan walk-through: Faster 10K, intermediate, no race date")
        line("Runs 4 days (long run Sunday), gym 5 days: Push, Pull, Legs, Upper, Shoulders & arms. Friday off.")
        line("Starting point: 15 km a week (the intermediate minimum), longest recent run 4.5 km.")
        line("Starting paces from the intermediate default (5K about 26:00): VDOT \(String(format: "%.1f", PaceZones(profile: profile).vdot)).")
        line()
        line("## The outline (set on day one)")
        for week in outline.weeks {
            let share = week.programmeWeek.flatMap(programme.week)?.volume
            let base = share.map { week.runVolumeMeters / $0 }
            let label = week.programmeWeek.map { "programme week \($0)" } ?? "recovery week after the programme"
            let lighter = week.isRecoveryWeek ? " · lighter" : ""
            var text = "- Week \(week.index + 1) (\(day(week.startDate))): \(week.phase.displayName)\(lighter), \(km(week.runVolumeMeters))"
            if let share, let base {
                let percent = Int((share * 100).rounded())
                text += " = \(percent)% of a base of \(km(base))"
            }
            text += " · \(label)"
            line(text)
        }
        line()

        var index = 0
        var previousPlanned: Double?
        while index < outline.weeks.count {
            let target = outline.weeks[index]
            guard var week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: workingWeights) else { break }
            let weekNumber = index + 1
            let programmeWeek = target.programmeWeek.flatMap(programme.week)
            let badWeek = weekNumber == 6
            var changesForThisWeek: [String] = []

            // Last week's check-in adjusts this week's sessions (as WeeklyCheckInService does).
            if let feel = pendingCheckIn {
                for i in week.sessions.indices {
                    switch week.sessions[i].kind {
                    case .run(let type):
                        guard let structure = week.sessions[i].runStructure else { continue }
                        if feel == .tooEasy && (type == .tempo || type == .intervals) { continue }
                        let factor = feel == .tooMuch ? 0.9 : 1.05
                        let scaled = WeekAdjustment.scaled(structure, by: factor)
                        guard scaled != structure else { continue }
                        let before = week.sessions[i].estimatedDistanceMeters ?? 0
                        week.sessions[i].runStructure = scaled
                        week.sessions[i].estimatedDistanceMeters = scaled.estimate(zones: PaceZones(profile: profile)).distanceMeters
                        changesForThisWeek.append("\(week.sessions[i].title) \(km(before)) → \(km(week.sessions[i].estimatedDistanceMeters ?? 0))")
                    case .strength:
                        guard feel == .tooMuch, let prescription = week.sessions[i].strength else { continue }
                        let lighter = WeekAdjustment.lighter(prescription)
                        guard lighter != prescription else { continue }
                        let before = prescription.exercises.reduce(0) { $0 + $1.sets }
                        let after = lighter.exercises.reduce(0) { $0 + $1.sets }
                        week.sessions[i].strength = lighter
                        changesForThisWeek.append("\(week.sessions[i].title) \(before) → \(after) sets")
                    default:
                        continue
                    }
                }
                pendingCheckIn = nil
            }

            let planned = week.sessions.compactMap(\.estimatedDistanceMeters).reduce(0, +)
            let long = week.sessions.first { $0.kind == .run(.long) }?.estimatedDistanceMeters
            var heading = "## Week \(weekNumber) · \(day(target.startDate)) · \(target.phase.displayName) week \(target.weekInPhase + 1)"
            if target.isRecoveryWeek { heading += " (lighter)" }
            if (target.programmeCycle ?? 1) > 1 { heading += " · second time through" }
            line(heading)
            var why = "Running: \(km(target.runVolumeMeters)) planned for the week"
            if let share = programmeWeek?.volume {
                why += " (\(Int((share * 100).rounded()))% of the base, now \(km(target.runVolumeMeters / share)))"
            }
            if let previousPlanned {
                let change = (target.runVolumeMeters / max(previousPlanned, 1) - 1) * 100
                why += String(format: ", %@%.0f%% on last week", change >= 0 ? "+" : "", change)
            }
            why += ". Sessions add up to \(km(planned))"
            if let long { why += ", long run \(km(long))" }
            line(why + ".")
            let emphasis = programmeWeek?.strength ?? (target.isRecoveryWeek ? "light" : "normal")
            line("Gym: \(emphasis) week" + (target.isRecoveryWeek ? " (one set fewer per exercise)." : "."))
            for note in week.notes { line("Coach's note: \(note)") }
            if !changesForThisWeek.isEmpty {
                line("Changed by last week's check-in: " + changesForThisWeek.joined(separator: "; ") + ".")
            }
            line()
            line("Sessions and what happened:")

            var doneMeters = 0.0
            var increases: [String] = []
            var holds: [String] = []
            var deloads: [String] = []
            for session in week.sessions.sorted(by: { $0.date == $1.date ? $0.slot.rawValue > $1.slot.rawValue : $0.date < $1.date }) {
                switch session.kind {
                case .run(let type):
                    var structure = session.runStructure ?? RunStructure(segments: [])
                    var meters = session.estimatedDistanceMeters ?? 0
                    var extra = ""
                    // The bad week: Wednesday's recovery is 55, so starting the session offers a cut.
                    if badWeek, calendar.component(.weekday, from: session.date) == 4 {
                        let weekSession = WeekSession(id: UUID(), date: session.date, slot: session.slot, kind: session.kind, isKey: false,
                                                      title: session.title, summary: session.summary,
                                                      durationMinutes: session.plannedDurationMinutes, effort: session.plannedEffort,
                                                      runStructure: structure)
                        if let option = Rebalancer.reduced(weekSession, recovery: RecoveryScore(score: 55, parts: [])),
                           let reduced = option.replacement.runStructure {
                            structure = reduced
                            meters = reduced.estimate(zones: PaceZones(profile: profile)).distanceMeters
                            extra = " → recovery 55 that morning: \(option.explanation) Ran \(km(meters))."
                        }
                    }
                    doneMeters += meters
                    // Interval reps from week 5 run about 3% quicker than the target.
                    if type == .intervals, weekNumber >= 5 {
                        let reps = structure.segments.filter { $0.kind == .work }.compactMap(\.targetPace)
                            .map { Pace(secondsPerKm: ($0.fastest.secondsPerKm + $0.slowest.secondsPerKm) / 2 * 0.97) }
                        if reps.count >= 3 {
                            evidence.append(FormEstimate.Evidence(date: session.date, bestEfforts: [:], intervalRepPaces: reps))
                            extra += " Reps averaged \(pace(reps[0].secondsPerKm)) (target about \(pace(reps[0].secondsPerKm / 0.97)))."
                        }
                    }
                    let typeName = type == .long ? "long" : type.rawValue
                    line("- \(day(session.date)) · \(session.title) (\(typeName)): \(session.summary)\(extra)")
                case .strength:
                    guard let prescription = session.strength else { continue }
                    var mains: [String] = []
                    for exercise in prescription.exercises {
                        guard let prescribed = exercise.weightKg else { continue } // bodyweight: no weight to progress
                        let key = exercise.progressionKey
                        let definition = templates.exercise(id: exercise.exerciseId)
                        var weight = workingWeights[key] ?? prescribed
                        if weight <= 0 {
                            // A machine with no default: the first session's weight becomes the working weight.
                            weight = definition?.region == .lower ? 40 : 20
                            workingWeights[key] = weight
                            states[key] = ProgressionState(workingWeightKg: weight)
                        }
                        let sets = lifter.sets(for: exercise, weight: weight, offDay: badWeek)
                        let decision = Progression.evaluate(
                            exerciseName: exercise.name, loading: definition?.loading ?? .barbell, region: definition?.region ?? .upper,
                            repRange: exercise.repRange, prescribedSets: exercise.sets,
                            state: states[key] ?? ProgressionState(workingWeightKg: weight), sets: sets, rules: rules)
                        if decision.change != .none {
                            states[key] = decision.newState
                            workingWeights[key] = decision.newState.workingWeightKg
                        }
                        lifter.trained(key, lightWeek: target.isRecoveryWeek)
                        let repsText = sets.map { String($0.reps) }.joined(separator: ", ")
                        if exercise.role == .main {
                            mains.append("\(exercise.name) \(kg(weight)) × \(repsText) (aim \(exercise.repRange.lower)–\(exercise.repRange.upper))")
                            mainLiftHistory[exercise.name, default: []].append((weekNumber, weight))
                        }
                        switch decision.change {
                        case .increase: increases.append(decision.reason)
                        case .deload: deloads.append(decision.reason)
                        case .hold where sets.contains(where: { $0.reps < exercise.repRange.lower }): holds.append(decision.reason)
                        default: break
                        }
                    }
                    let totalSets = prescription.exercises.reduce(0) { $0 + $1.sets }
                    var text = "- \(day(session.date)) · \(session.title): \(prescription.exercises.count) exercises, \(totalSets) sets."
                    if !mains.isEmpty { text += " Main lifts: " + mains.joined(separator: "; ") + "." }
                    line(text)
                case .crossTraining, .mobility:
                    line("- \(day(session.date)) · \(session.title): \(session.summary)")
                }
            }
            actualWeekMeters.append(doneMeters)
            line()
            line("Ran \(km(doneMeters)) of \(km(planned)) planned.")
            if !increases.isEmpty { line("Weights going up for the next session:"); increases.forEach { line("  - \($0)") } }
            if !holds.isEmpty { line("Weights held (reps fell short):"); holds.forEach { line("  - \($0)") } }
            if !deloads.isEmpty { line("Weights reset:"); deloads.forEach { line("  - \($0)") } }
            let inRange = week.sessions.compactMap(\.strength).flatMap(\.exercises).filter { $0.weightKg != nil }.count
                - increases.count - holds.count - deloads.count
            if inRange > 0 { line("  (\(inRange) other exercises stay at their weight: reps still climbing towards the top of the range.)") }

            // What carries into next week.
            var carried: [String] = []
            if weekNumber == 2 {
                pendingCheckIn = .tooEasy
                carried.append("Weekly check-in: \"too easy\" → next week's easy, steady and long runs about 5% longer (intervals stay as planned).")
            }
            if badWeek {
                pendingCheckIn = .tooMuch
                carried.append("Weekly check-in: \"too much\" → next week's runs about 10% shorter (intervals one rep fewer) and one set fewer on gym accessories. The week after goes back to the plan.")
            }
            let now = calendar.date(byAdding: .day, value: 7, to: target.startDate) ?? target.startDate
            let currentVDOT = PaceZones(profile: profile).vdot
            if !paceOfferTaken, let form = FormEstimate.estimate(evidence, current: currentVDOT, now: now) {
                if form.vdot >= currentVDOT * 1.02 && form.sessions >= 2 {
                    let before = PaceZones(vdot: currentVDOT)
                    let after = PaceZones(vdot: form.vdot)
                    profile.recentRace = RaceResult(distanceMeters: 10000, timeSeconds: after.predictedTime(distanceMeters: 10000).rounded())
                    outline = generator.makeOutline(for: profile, startingOn: start)
                    paceOfferTaken = true
                    let easyBefore = before.range(for: .easy), easyAfter = after.range(for: .easy)
                    let intBefore = before.range(for: .interval), intAfter = after.range(for: .interval)
                    let vdotText = String(format: "%.1f", form.vdot), wasText = String(format: "%.1f", currentVDOT)
                    let tenBefore = Units.formatMinutesSeconds(before.predictedTime(distanceMeters: 10000))
                    let tenAfter = Units.formatMinutesSeconds(after.predictedTime(distanceMeters: 10000))
                    let easyText = "\(pace(easyBefore.slowest.secondsPerKm))–\(pace(easyBefore.fastest.secondsPerKm)) → \(pace(easyAfter.slowest.secondsPerKm))–\(pace(easyAfter.fastest.secondsPerKm))"
                    let intervalText = "\(pace(intBefore.fastest.secondsPerKm)) → \(pace(intAfter.fastest.secondsPerKm))"
                    var text = "Faster paces: your interval reps show fitness of VDOT \(vdotText) (was \(wasText)). "
                    text += "The app offers to update your paces; accepted, so the plan is rebuilt from today with them. "
                    text += "10K prediction \(tenBefore) → \(tenAfter); easy \(easyText); intervals \(intervalText). Weekly distances stay the same."
                    carried.append(text)
                } else if weekNumber >= 5 {
                    let vdotText = String(format: "%.1f", form.vdot), currentText = String(format: "%.1f", currentVDOT)
                    carried.append("Form check: VDOT \(vdotText) from \(form.sessions) session(s), not yet 2% above your paces' \(currentText), so paces stay.")
                }
            }
            if index + 1 < outline.weeks.count {
                let next = outline.weeks[index + 1]
                let ending = next.isRecoveryWeek ? " (a lighter week)." : "."
                carried.append("Next week's distance, \(km(next.runVolumeMeters)), was set on day one and doesn't depend on how this week went" + ending)
            }
            carried.append("Gym: every session uses the latest working weights (sessions already planned update as soon as a weight changes).")
            line()
            line("Into next week:")
            carried.forEach { line("  - \($0)") }
            line()

            let mainsNow = ["Squat", "Bench", "Deadlift", "Overhead", "Row"].compactMap { name -> String? in
                guard let entry = mainLiftHistory.first(where: { $0.key.contains(name) })?.value.last else { return nil }
                return "\(name) \(kg(entry.kg))"
            }
            let light = target.isRecoveryWeek ? " (light)" : ""
            let longText = long.map { km($0) } ?? "–"
            summaryRows.append("| \(weekNumber) | \(target.phase.displayName)\(light) | \(km(target.runVolumeMeters)) | \(km(doneMeters)) | \(longText) | \(mainsNow.joined(separator: ", ")) |")

            // Volume never more than 10% above the biggest of the last three planned weeks (as built).
            if index >= 1 {
                let recent = outline.weeks[max(0, index - 3)..<index].map(\.runVolumeMeters).max() ?? target.runVolumeMeters
                XCTAssertLessThanOrEqual(target.runVolumeMeters, recent * 1.1 + 1, "Week \(weekNumber) jumps too much")
            }
            previousPlanned = target.runVolumeMeters
            index += 1

            // After the programme's recovery week: the next time through, from what they actually ran.
            if index == outline.weeks.count, !cycleExtended {
                let recent = actualWeekMeters.suffix(4).reduce(0, +) / Double(min(4, actualWeekMeters.count))
                if let extended = generator.nextCycle(of: outline, profile: profile, recentWeeklyRunMeters: recent) {
                    cycleExtended = true
                    line("## The programme starts again")
                    let firstStart = km(outline.weeks[0].runVolumeMeters)
                    line("Your last four weeks averaged \(km(recent)). The second time through starts from that (the first started from \(firstStart)), building towards the intermediate race-ready volume of 40 km at up to 10% a week.")
                    line()
                    // Two weeks of it are enough to show where it starts.
                    outline = extended
                    outline.weeks = Array(outline.weeks.prefix(index + 2))
                }
            }
        }

        line("## Summary")
        line("| Week | Phase | Planned | Ran | Long run | Main lifts (working weight at the last session) |")
        line("|---|---|---|---|---|---|")
        summaryRows.forEach { line($0) }

        print("\n===== PLAN SIMULATION =====\n" + report.joined(separator: "\n") + "\n===== END PLAN SIMULATION =====\n")

        // Lifts move up over the plan.
        let grew = mainLiftHistory.values.filter { history in (history.last?.kg ?? 0) > (history.first?.kg ?? 0) }
        XCTAssertFalse(grew.isEmpty, "At least one main lift should get heavier")
    }
}
