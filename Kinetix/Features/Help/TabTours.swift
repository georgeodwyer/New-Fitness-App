import SwiftUI

/// A short tour the first time each tab is opened: a few steps in one card at the top, with
/// Next, Back and Skip. Each tab's tour shows once; Settings → Help & about shows them again.
enum TabTours {
    enum Tab: String, CaseIterable {
        case today, plan, workout, activity, profile
    }

    struct Step: Identifiable {
        let symbol: String
        let title: String
        let text: String
        var id: String { title }
    }

    static func key(_ tab: Tab) -> String { "tour.\(tab.rawValue).done" }

    /// Hidden for UI tests so screenshots and taps see the normal screen.
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }

    static func resetAll(defaults: UserDefaults = .standard) {
        for tab in Tab.allCases { defaults.removeObject(forKey: key(tab)) }
        defaults.removeObject(forKey: GettingStartedCard.hiddenKey)
        WorkoutHints.resetAll(defaults: defaults)
    }

    static func steps(_ tab: Tab) -> [Step] {
        switch tab {
        case .today:
            return [
                Step(symbol: "sun.max", title: "Your day at a glance",
                     text: "Today's session is at the top. Tap Start to begin, or the session for its details."),
                Step(symbol: "gauge.with.needle", title: "Readiness",
                     text: "Check in each morning (sleep, energy, soreness). With Apple Health it gives a recovery score, and your session can be eased on a tough day."),
                Step(symbol: "square.grid.2x2", title: "Make it yours",
                     text: "Tap ••• then Edit dashboard to add more cards, like this week against plan or records, or to reorder them."),
            ]
        case .plan:
            return [
                Step(symbol: "calendar", title: "Your weeks",
                     text: "Every run and gym session, week by week. Tap a week to open it and a session to see exactly what to do."),
                Step(symbol: "slider.horizontal.3", title: "Life happens",
                     text: "Adjust plan lets you rearrange days, pause for illness or travel, or review last week."),
                Step(symbol: "arrow.triangle.2.circlepath", title: "It adapts",
                     text: "Kinetix updates your plan from what you actually do. The bell on Today shows what changed and why."),
            ]
        case .workout:
            return [
                Step(symbol: "play.circle", title: "Start anything",
                     text: "Today's planned session is at the top. Or start a run, gym session or functional workout on its own."),
                Step(symbol: "books.vertical", title: "Your own workouts",
                     text: "Open Your workouts and routes to build, save and share workouts, browse the workout bank or plan a route."),
            ]
        case .activity:
            return [
                Step(symbol: "list.bullet", title: "Feed",
                     text: "Every session you've done, newest first, including workouts from other apps."),
                Step(symbol: "chart.bar", title: "Stats",
                     text: "Totals and your training calendar, with Running, Strength and Health for pace trends, best efforts, lifts and body data."),
                Step(symbol: "trophy", title: "Achievements",
                     text: "Points for sticking to your plan, levels, badges and monthly challenges, and friends to compete with."),
            ]
        case .profile:
            return [
                Step(symbol: "person.crop.circle", title: "You",
                     text: "Your goal and level. Tap your level for achievements."),
                Step(symbol: "wrench.and.screwdriver", title: "Tools",
                     text: "Pace calculator, split planner and converter for race planning and treadmills."),
                Step(symbol: "gearshape", title: "Settings",
                     text: "The cog has your training profile, watch and apps, notifications, and Help & questions."),
            ]
        }
    }
}

/// The tour card at the top of a tab (nothing once it's done).
struct TabTourCard: View {
    let tab: TabTours.Tab
    @AppStorage private var done: Bool
    @State private var index = 0

    init(_ tab: TabTours.Tab) {
        self.tab = tab
        _done = AppStorage(wrappedValue: false, TabTours.key(tab))
    }

    var body: some View {
        let steps = TabTours.steps(tab)
        if !done && !TabTours.isUITesting && steps.indices.contains(index) {
            let step = steps[index]
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    Image(systemName: step.symbol)
                        .font(.title2)
                        .foregroundStyle(KXColor.onAccent)
                        .frame(width: 44, height: 44)
                        .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        KXOverline("Quick tour · \(index + 1) of \(steps.count)", color: KXColor.accent)
                        Text(step.title).font(KXFont.headline).foregroundStyle(KXColor.ink)
                        Text(step.text).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: KXSpacing.sm) {
                    Button("Skip") { finish() }
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                        .accessibilityIdentifier("tour.skip")
                    Spacer()
                    if index > 0 {
                        Button("Back") { withAnimation { index -= 1 } }
                            .buttonStyle(.kx(.secondary))
                    }
                    Button(index == steps.count - 1 ? "Got it" : "Next") {
                        if index == steps.count - 1 { finish() } else { withAnimation { index += 1 } }
                    }
                    .buttonStyle(.kx(.primary))
                    .accessibilityIdentifier("tour.next")
                }
            }
            .kxCard(.accent)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .contain)
        }
    }

    private func finish() {
        withAnimation { done = true }
        index = 0
    }
}

/// One-time hints during someone's first run, gym session and functional workout.
enum WorkoutHints {
    enum Kind: String, CaseIterable { case run, gym, functional }

    static func key(_ kind: Kind) -> String { "hint.\(kind.rawValue).done" }

    static func resetAll(defaults: UserDefaults = .standard) {
        for kind in Kind.allCases { defaults.removeObject(forKey: key(kind)) }
    }

    static func text(_ kind: Kind) -> String {
        switch kind {
        case .run: return "First run with Kinetix: your target pace is shown big, and the voice coach tells you if you're too fast or too slow. Pause and End are at the bottom; the run is saved when you end it."
        case .gym: return "First gym session: log each set as you finish it and the rest timer starts. If the weight or reps were different, change them first so your next session is set right."
        case .functional: return "First functional workout: the clock runs the whole workout. Follow the station shown and move on as each one is done."
        }
    }
}

/// A dismissible hint shown once, at the top of a workout screen.
struct WorkoutHintBanner: View {
    let kind: WorkoutHints.Kind
    @AppStorage private var done: Bool

    init(_ kind: WorkoutHints.Kind) {
        self.kind = kind
        _done = AppStorage(wrappedValue: false, WorkoutHints.key(kind))
    }

    var body: some View {
        if !done && !TabTours.isUITesting {
            HStack(alignment: .top, spacing: KXSpacing.sm) {
                Image(systemName: "lightbulb.fill").foregroundStyle(KXColor.warning).accessibilityHidden(true)
                Text(WorkoutHints.text(kind)).font(KXFont.caption).foregroundStyle(KXColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { withAnimation { done = true } } label: {
                    Image(systemName: "xmark").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                .accessibilityLabel("Dismiss hint")
            }
            .padding(KXSpacing.md)
            .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .accessibilityIdentifier("hint.\(kind.rawValue)")
        }
    }
}
