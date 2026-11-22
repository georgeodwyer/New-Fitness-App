import SwiftUI
import TrainingEngine

/// The goal on Today: "HALF MARATHON · 112 DAYS", your predicted time now against your goal time,
/// and how the prediction has moved in the last four weeks (or where you are in the block until
/// there's four weeks of history). Tap for the plan's phases.
struct GoalTodayCard: View {
    let outline: PlanOutline
    let profile: AthleteProfile?

    @State private var showPhases = false
    private var calendar: Calendar { .kinetix }

    private var currentIndex: Int? { outline.weekIndex(containing: .now, calendar: calendar) }

    private var daysToRace: Int? {
        guard let event = outline.eventDate else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: event)).day
    }

    private var predicted: Double? {
        guard let profile, let meters = profile.goal.raceDistanceMeters else { return nil }
        return PaceZones(vdot: FormService.predictionVDOT(for: profile)).predictedTime(distanceMeters: meters)
    }

    private var heading: String {
        var parts = [profile?.goal.displayName.uppercased() ?? "YOUR PLAN"]
        if let days = daysToRace {
            parts.append(days > 0 ? "\(days) DAY\(days == 1 ? "" : "S")" : "RACE DAY")
        } else if let index = currentIndex {
            parts.append("WEEK \(index + 1) OF \(outline.weeks.count)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let prediction = predicted
        let change = prediction.flatMap { PredictionHistory.change(now: $0, goal: profile?.goal) }
        Button { showPhases = true } label: {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                KXOverline(heading)
                if let prediction {
                    HStack(alignment: .top) {
                        column("Predicted now", Units.formatMinutesSeconds(prediction), primary: true)
                        if let goal = profile?.goalTimeSeconds {
                            column("Your goal", Units.formatMinutesSeconds(goal), primary: false)
                        } else if let index = currentIndex {
                            column("Your block", "Week \(index + 1) of \(outline.weeks.count)", primary: false)
                        }
                    }
                } else if let index = currentIndex {
                    column("Your block", "Week \(index + 1) of \(outline.weeks.count)", primary: true)
                }
                strip(change: change, prediction: prediction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every phase of your plan")
        .accessibilityIdentifier("today.goal")
        .sheet(isPresented: $showPhases) { PlanPhasesView(outline: outline) }
        .onAppear { if let prediction { PredictionHistory.record(prediction, goal: profile?.goal) } }
    }

    private func column(_ label: String, _ value: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            Text(value)
                .font(KXFont.number(30, relativeTo: .title))
                .foregroundStyle(primary ? KXColor.ink : KXColor.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "↓ 1:40 faster than 4 weeks ago · 2:11 to go", else this week's phase.
    @ViewBuilder
    private func strip(change: Double?, prediction: Double?) -> some View {
        if let change, abs(change) >= 1 {
            let faster = change < 0
            let toGo = profile?.goalTimeSeconds.flatMap { goal in prediction.map { $0 - goal } }
            HStack(spacing: KXSpacing.sm) {
                Text("\(faster ? "↓" : "↑") \(Units.formatMinutesSeconds(abs(change)))")
                    .font(KXFont.bodyEmphasis)
                    .foregroundStyle(faster ? KXColor.success : KXColor.warning)
                Text((faster ? "faster" : "slower") + " than 4 weeks ago"
                     + (toGo.map { $0 > 0 ? " · \(Units.formatMinutesSeconds($0)) to go" : " · on goal pace" } ?? ""))
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.ink)
                Spacer(minLength: 0)
            }
            .padding(KXSpacing.sm)
            .background((faster ? KXColor.success : KXColor.warning).opacity(0.14), in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        } else if let index = currentIndex {
            let week = outline.weeks[index]
            Text("Week \(index + 1) of \(outline.weeks.count) · \(week.phase.displayName)\(week.isRecoveryWeek ? " · easier week" : "")")
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkSecondary)
        }
    }
}

/// The predicted race time, kept once a day, so Today can say how it's moved over four weeks.
enum PredictionHistory {
    static let key = "goal.predictionHistory"

    private static func load(_ defaults: UserDefaults) -> [String: Double] {
        (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }

    private static func day(_ date: Date) -> String {
        let parts = Calendar.kinetix.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Saves today's prediction (one per day, a year kept). A new goal starts a new history.
    static func record(_ seconds: Double, goal: TrainingGoal?, now: Date = .now, defaults: UserDefaults = .standard) {
        let goalKey = "goal.predictionHistory.goal"
        let goalName = goal.map { String(describing: $0) } ?? ""
        var history = load(defaults)
        if defaults.string(forKey: goalKey) != goalName {
            history = [:]
            defaults.set(goalName, forKey: goalKey)
        }
        history[day(now)] = seconds
        let cutoff = day(now.addingTimeInterval(-366 * 86_400))
        history = history.filter { $0.key >= cutoff }
        defaults.set(history, forKey: key)
    }

    /// Seconds faster (negative) or slower than the prediction about four weeks ago (nil when
    /// there isn't one from 4 to 6 weeks back).
    static func change(now seconds: Double, goal: TrainingGoal?, now date: Date = .now, defaults: UserDefaults = .standard) -> Double? {
        let goalName = goal.map { String(describing: $0) } ?? ""
        guard defaults.string(forKey: "goal.predictionHistory.goal") == goalName else { return nil }
        let history = load(defaults)
        let newest = day(date.addingTimeInterval(-28 * 86_400))
        let oldest = day(date.addingTimeInterval(-42 * 86_400))
        guard let then = history.filter({ $0.key <= newest && $0.key >= oldest }).max(by: { $0.key < $1.key })?.value else { return nil }
        return seconds - then
    }
}
