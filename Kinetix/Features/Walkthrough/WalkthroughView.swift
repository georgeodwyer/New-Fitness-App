import SwiftUI

/// Whether the tour still needs showing. Set when a plan is first built; cleared when the tour
/// is finished or skipped. It can be replayed any time from Settings.
enum Walkthrough {
    private static let pendingKey = "walkthrough.pending"

    static var isPending: Bool {
        get { UserDefaults.standard.bool(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }
}

/// A short swipeable tour of the app: what each tab does and how the plan adapts.
struct WalkthroughView: View {
    /// Called when the tour closes. `openToday` is true when they tapped the final button.
    let onDone: (_ openToday: Bool) -> Void
    @State private var page = 0

    private let pages = WalkthroughPage.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages.count - 1 {
                    Button("Skip") { finish(openToday: false) }
                        .font(KXFont.bodyEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                        .accessibilityIdentifier("walkthrough.skip")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, KXSpacing.screenMargin)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    WalkthroughPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            VStack(spacing: KXSpacing.lg) {
                HStack(spacing: KXSpacing.sm) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? KXColor.accent : KXColor.border)
                            .frame(width: index == page ? 20 : 8, height: 8)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: page)
                .accessibilityElement()
                .accessibilityLabel("Page \(page + 1) of \(pages.count)")

                Button(page == pages.count - 1 ? "Let's go" : "Next") {
                    if page == pages.count - 1 { finish(openToday: true) } else { page += 1 }
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("walkthrough.next")
            }
            .padding(.horizontal, KXSpacing.screenMargin)
            .padding(.bottom, KXSpacing.lg)
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private func finish(openToday: Bool) {
        Walkthrough.isPending = false
        onDone(openToday)
    }
}

// MARK: - Pages

struct WalkthroughPage: Sendable {
    let plain: String
    let accented: String
    let detail: String
    let points: [(symbol: String, text: String)]
    let illustration: Illustration

    enum Illustration { case welcome, today, plan, adapts, record, progress, connect, help }

    static let all: [WalkthroughPage] = [
        WalkthroughPage(
            plain: "Welcome to", accented: "Kinetix",
            detail: "Running and strength in one plan that adjusts to you. Here's a one-minute tour.",
            points: [
                ("calendar", "Your plan mixes runs and gym sessions so they help each other, not compete."),
                ("heart.text.square", "It reads how recovered you are and adjusts the day."),
                ("arrow.uturn.backward", "Every change is explained, and you're always in control."),
            ],
            illustration: .welcome),
        WalkthroughPage(
            plain: "Start each day on", accented: "Today",
            detail: "Everything you need for today, in one place.",
            points: [
                ("gauge.with.needle", "Recovery: how ready your body is, out of 100, with your HRV, resting heart rate and sleep under it. About 72 is a normal day; 85+ is great."),
                ("hand.raised", "No sleep data (watch charging overnight)? Tap \"Don't wait\" and your check-in sets the score."),
                ("flame", "Exertion: how hard you've worked today, against a target for the day."),
                ("checkmark.circle", "Your score: a 10-second check-in on sleep, legs, upper body and energy."),
                ("arrow.down", "Pull down to refresh your Apple Health data."),
            ],
            illustration: .today),
        WalkthroughPage(
            plain: "Your", accented: "plan",
            detail: "The Plan tab lays out every week, building towards your goal.",
            points: [
                ("flag.checkered", "A countdown to race day and the phase you're in."),
                ("chart.bar", "This week's distance against the plan, and earlier weeks kept for reference."),
                ("calendar", "Tap This week on Today for the full calendar."),
                ("arrow.triangle.2.circlepath", "Change your goal or days in Settings and rebuild from today, keeping your progress."),
            ],
            illustration: .plan),
        WalkthroughPage(
            plain: "A plan that", accented: "adapts",
            detail: "Your plan isn't fixed. It responds to how you're doing.",
            points: [
                ("arrow.down.right", "Low recovery: today's hard sessions are eased for you."),
                ("hand.raised", "Fair recovery: you're offered a lighter version. Your choice."),
                ("calendar.badge.clock", "Busy day? Move a session to another day from its menu."),
                ("arrow.uturn.backward", "Every change shows why it happened, and you can undo it."),
            ],
            illustration: .adapts),
        WalkthroughPage(
            plain: "Record runs and", accented: "lifts",
            detail: "Start today's session from Today, or anything else from Record.",
            points: [
                ("figure.run", "Runs: live pace, distance and heart rate, with audio coaching. Tap the big number to switch it."),
                ("trophy", "Racing? Choose Race: a new best updates your paces and plan."),
                ("dumbbell", "Gym: sets, reps and weights, with a rest timer. Finish early if you're short on time."),
                ("applewatch", "Apple Watch: run from your wrist and build your own watch screens in Settings."),
            ],
            illustration: .record),
        WalkthroughPage(
            plain: "See your", accented: "progress",
            detail: "The Progress tab shows what your training is adding up to.",
            points: [
                ("speedometer", "Your paces for every type of run, and race time predictions."),
                ("trophy", "Best efforts over each running distance, and records for every lift."),
                ("chart.line.uptrend.xyaxis", "Each lift's working weight and estimated 1-rep max over time."),
            ],
            illustration: .progress),
        WalkthroughPage(
            plain: "Connect your", accented: "apps",
            detail: "Optional, but they make Kinetix much smarter. Set them up in Settings.",
            points: [
                ("heart.fill", "Apple Health: sleep, HRV and resting heart rate power your recovery score."),
                ("applewatch", "Apple Watch: runs and gym sessions on your wrist, with screens you design."),
                ("arrow.triangle.2.circlepath", "Strava: send your runs and lifts there automatically."),
                ("bell", "Notifications: a morning summary of the day, and rest timer alerts."),
            ],
            illustration: .connect),
        WalkthroughPage(
            plain: "You're", accented: "all set",
            detail: "Change your goal, days or gym kit any time in Settings, and your plan rebuilds around it.",
            points: [
                ("questionmark.circle", "Watch this tour again in Settings → App tour."),
                ("info.circle", "Tap any session to see what it's for and how to do it."),
            ],
            illustration: .help),
    ]
}

private struct WalkthroughPageView: View {
    let page: WalkthroughPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                WalkthroughIllustration(kind: page.illustration)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                OnboardingQuestion(plain: page.plain, accented: page.accented, detail: page.detail)
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    ForEach(page.points.indices, id: \.self) { index in
                        let point = page.points[index]
                        HStack(alignment: .top, spacing: KXSpacing.md) {
                            Image(systemName: point.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(KXColor.accent)
                                .frame(width: 24)
                            Text(point.text)
                                .font(KXFont.body)
                                .foregroundStyle(KXColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(KXSpacing.screenMargin)
        }
    }
}

// MARK: - Illustrations

/// Simple drawn previews of each screen, built from the app's own colours (no screenshots, so
/// they stay right in light and dark mode and never go out of date with real data).
private struct WalkthroughIllustration: View {
    let kind: WalkthroughPage.Illustration

    var body: some View {
        Group {
            switch kind {
            case .welcome: welcome
            case .today: today
            case .plan: plan
            case .adapts: adapts
            case .record: record
            case .progress: progress
            case .connect: connect
            case .help: help
            }
        }
        .frame(height: 200)
    }

    private var welcome: some View {
        HStack(spacing: KXSpacing.lg) {
            bubble("figure.run", KXColor.run)
            Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(KXColor.inkTertiary)
            bubble("dumbbell.fill", KXColor.lift)
        }
    }

    private var today: some View {
        miniCard {
            VStack(spacing: KXSpacing.sm) {
                ZStack {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(KXColor.border, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    Circle().trim(from: 0, to: 0.75 * 0.78)
                        .stroke(AngularGradient(colors: [KXColor.danger, KXColor.warning, KXColor.success], center: .center,
                                                startAngle: .degrees(0), endAngle: .degrees(270)),
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    VStack(spacing: 0) {
                        Text("RECOVERY").font(KXFont.overline).foregroundStyle(KXColor.inkSecondary)
                        Text("78").font(KXFont.number(30)).foregroundStyle(KXColor.ink)
                    }
                }
                .frame(width: 96, height: 96)
                Capsule().fill(KXColor.surfaceTint).frame(height: 6)
                    .overlay(alignment: .leading) { Capsule().fill(KXColor.accent).frame(width: 110, height: 6) }
                HStack {
                    stat("61", "HRV ms")
                    Spacer()
                    stat("49", "rest bpm")
                    Spacer()
                    stat("7:12", "sleep")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 320)
    }

    private var plan: some View {
        VStack(spacing: KXSpacing.sm) {
            miniCard {
                HStack {
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text("RACE DAY").font(KXFont.overline).foregroundStyle(KXColor.inkSecondary)
                        Text("Half marathon").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    }
                    Spacer()
                    Text("47 days").font(KXFont.number(26)).foregroundStyle(KXColor.accent)
                }
            }
            miniCard {
                HStack(alignment: .bottom, spacing: KXSpacing.sm) {
                    ForEach(Self.bars.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(index == 4 ? KXColor.accent : KXColor.run.opacity(0.55))
                            .frame(height: 60 * Self.bars[index])
                    }
                }
                .frame(height: 64, alignment: .bottom)
            }
        }
        .frame(maxWidth: 320)
    }

    private var adapts: some View {
        VStack(spacing: KXSpacing.sm) {
            sessionRow("figure.run", KXColor.inkTertiary, "Intervals", "6 × 800 m", struck: true)
            Image(systemName: "arrow.down").font(.headline).foregroundStyle(KXColor.accent)
            sessionRow("figure.run", KXColor.run, "Easy run", "Eased: recovery is low")
            Label("Undo", systemImage: "arrow.uturn.backward")
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.accent)
        }
        .frame(maxWidth: 320)
    }

    private var record: some View {
        miniCard {
            VStack(spacing: KXSpacing.sm) {
                Text("5:12 /km").font(KXFont.metric).foregroundStyle(KXColor.ink)
                HStack(spacing: KXSpacing.xl) {
                    stat("4.2", "km")
                    stat("21:48", "time")
                    stat("152", "bpm")
                }
                Capsule().fill(KXColor.accent).frame(width: 64, height: 6)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 320)
    }

    private static let bars: [CGFloat] = [0.35, 0.5, 0.45, 0.65, 0.6, 0.8, 0.95]

    private var progress: some View {
        miniCard {
            HStack(alignment: .bottom, spacing: KXSpacing.sm) {
                ForEach(Self.bars.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index == Self.bars.count - 1 ? KXColor.accent : KXColor.lift.opacity(0.6))
                        .frame(height: 120 * Self.bars[index])
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
        .frame(maxWidth: 320)
    }

    private var connect: some View {
        HStack(spacing: KXSpacing.lg) {
            bubble("heart.fill", KXColor.danger)
            bubble("applewatch", KXColor.ink)
            bubble("arrow.triangle.2.circlepath", KXColor.accent)
        }
    }

    private var help: some View {
        bubble("checkmark", KXColor.success, size: 110)
    }

    // MARK: Pieces

    private func bubble(_ symbol: String, _ tint: Color, size: CGFloat = 84) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(KXColor.surface, in: Circle())
            .overlay(Circle().stroke(KXColor.border, lineWidth: 1))
    }

    private func miniCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(KXSpacing.md)
            .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.border, lineWidth: 1))
    }

    private func sessionRow(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, struck: Bool = false) -> some View {
        miniCard {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(title).font(KXFont.bodyEmphasis).foregroundStyle(struck ? KXColor.inkTertiary : KXColor.ink).strikethrough(struck)
                    Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: KXSpacing.xxs) {
            Text(value).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
            Text(label).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }
}

#Preview {
    WalkthroughView { _ in }
}
