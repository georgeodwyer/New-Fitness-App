import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// Lock screen and Dynamic Island while a run or gym session is in progress (iOS 17).
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        WorkoutActivityLayout.configuration { context in
            LockScreenWorkoutView(title: context.attributes.title, kind: context.attributes.kind, state: context.state)
        }
    }
}

/// iOS 18 and later: the same, plus a layout made for Apple Watch. Without it the watch shows
/// the tiny Dynamic Island version (an icon and the distance) when it shows the iPhone's
/// workout in the Smart Stack.
@available(iOS 18.0, *)
struct WorkoutLiveActivityWithWatch: Widget {
    var body: some WidgetConfiguration {
        WorkoutActivityLayout.configuration { context in
            FamilyWorkoutView(title: context.attributes.title, kind: context.attributes.kind, state: context.state)
        }
        .supplementalActivityFamilies([.small])
    }
}

enum WorkoutActivityLayout {
    static func configuration<Content: View>(
        @ViewBuilder lockScreen: @escaping (ActivityViewContext<WorkoutActivityAttributes>) -> Content
    ) -> some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(KXColor.surface)
                .activitySystemActionForegroundColor(KXColor.accent)
                .widgetURL(URL(string: "kinetix://workout"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        WorkoutClock(state: state).font(.title2.weight(.semibold).monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.mode == .resting || state.mode == .lifting {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Sets").font(.caption).foregroundStyle(.secondary)
                            Text("\(state.setsDone ?? 0)/\(state.setsTotal ?? 0)").font(.title2.weight(.semibold).monospacedDigit())
                        }
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Pace").font(.caption).foregroundStyle(.secondary)
                            Text(state.pace ?? "--:--").font(.title2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(PaceStatusStyle(state.paceStatus).color)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let step = state.step ?? state.nextSet {
                            Text(step + (state.stepDetail.map { " · \($0)" } ?? "")).font(.caption).lineLimit(1)
                        } else if let distance = state.distance {
                            Text(distance).font(.caption.monospacedDigit())
                        }
                        Spacer()
                        if context.attributes.kind == "run" {
                            Button(intent: ToggleWorkoutPauseIntent()) {
                                Image(systemName: state.mode == .paused ? "play.fill" : "pause.fill")
                            }
                            .tint(KXColor.accent)
                        }
                    }
                }
            } compactLeading: {
                WorkoutKindIcon(kind: context.attributes.kind, size: 16)
                    .foregroundStyle(KXColor.accent)
            } compactTrailing: {
                // The gym has no pace: always the clock (rest countdown, set or session time).
                if state.mode == .resting || context.attributes.kind != "run" {
                    WorkoutClock(state: state).monospacedDigit().frame(maxWidth: 52)
                        .foregroundStyle(state.mode == .resting ? KXColor.accent : KXColor.ink)
                } else {
                    Text(state.pace ?? state.distance ?? "").monospacedDigit()
                        .foregroundStyle(PaceStatusStyle(state.paceStatus).color)
                }
            } minimal: {
                // Shared with another app's activity: the timer matters more than an icon.
                WorkoutClock(state: state)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(KXColor.accent)
            }
            .keylineTint(KXColor.accent)
        }
    }
}

/// Picks the layout for where the activity is shown: the full lock screen card on iPhone,
/// a compact one on Apple Watch.
@available(iOS 18.0, *)
struct FamilyWorkoutView: View {
    let title: String
    let kind: String
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small: WatchWorkoutView(title: title, kind: kind, state: state)
        default: LockScreenWorkoutView(title: title, kind: kind, state: state)
        }
    }
}

/// The Apple Watch layout: the interval step, pace against target, then time, distance
/// and heart rate (or the rest timer and next set in the gym).
struct WatchWorkoutView: View {
    let title: String
    let kind: String
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                WorkoutKindIcon(kind: kind, size: 14).foregroundStyle(KXColor.accent)
                Text(headline).font(.caption2.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if state.mode == .paused {
                    Image(systemName: "pause.circle.fill").foregroundStyle(KXColor.inkSecondary)
                } else if let hr = state.heartRate {
                    Label("\(hr)", systemImage: "heart.fill").font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(KXColor.danger).labelStyle(.titleAndIcon)
                }
            }
            if kind == "run" { run } else { strength }
        }
        .foregroundStyle(KXColor.ink)
        .padding(.horizontal, 2)
    }

    private var headline: String {
        guard let step = state.step else { return title }
        return step + (state.stepDetail.map { " · \($0)" } ?? "")
    }

    private var run: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.pace ?? "--:--")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(PaceStatusStyle(state.paceStatus).color)
                if let target = state.target {
                    Text(target).font(.caption2.monospacedDigit()).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                WorkoutClock(state: state)
                Text(state.distance ?? "0.00")
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(KXColor.inkSecondary)
        }
    }

    private var strength: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                WorkoutClock(state: state).font(.title3.weight(.bold).monospacedDigit())
                Text(state.mode == .resting ? "rest" : "\(state.setsDone ?? 0)/\(state.setsTotal ?? 0) sets")
                    .font(.caption2).foregroundStyle(KXColor.inkSecondary)
            }
            if let next = state.nextSet {
                Text("Next: \(next)").font(.caption2.weight(.semibold)).lineLimit(1)
            }
        }
    }
}

/// Counts up while running, holds while paused, counts down during a rest.
struct WorkoutClock: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.mode == .resting, let end = state.restEndsAt, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
        } else if state.mode == .running || state.mode == .lifting, let start = state.timerStart {
            Text(start, style: .timer)
        } else {
            Text(Self.format(state.elapsedSeconds))
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct PaceStatusStyle {
    let color: Color
    let symbol: String?
    let label: String?

    init(_ status: String?) {
        switch status {
        case "onTarget": color = KXColor.success; symbol = "checkmark.circle.fill"; label = "On target"
        case "tooFast": color = KXColor.warning; symbol = "hare.fill"; label = "Too fast"
        case "tooSlow": color = KXColor.warning; symbol = "tortoise.fill"; label = "Too slow"
        default: color = KXColor.ink; symbol = nil; label = nil
        }
    }
}

struct LockScreenWorkoutView: View {
    let title: String
    let kind: String
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WorkoutKindIcon(kind: kind, size: 14).foregroundStyle(KXColor.accent)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(KXColor.ink).lineLimit(1)
                Spacer()
                if state.mode == .paused {
                    Label("Paused", systemImage: "pause.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(KXColor.inkSecondary)
                }
                if kind == "run" {
                    Button(intent: ToggleWorkoutPauseIntent()) {
                        Image(systemName: state.mode == .paused ? "play.fill" : "pause.fill")
                            .font(.body.weight(.semibold))
                    }
                    .tint(KXColor.accent)
                    .accessibilityLabel(state.mode == .paused ? "Resume" : "Pause")
                }
            }
            if kind == "run" { runBody } else { strengthBody }
        }
        .padding(16)
    }

    private var runBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                metric("Time") { WorkoutClock(state: state) }
                Spacer()
                metric("Distance") { Text(state.distance ?? "0.00") }
                Spacer()
                metric("Pace") {
                    Text(state.pace ?? "--:--").foregroundStyle(PaceStatusStyle(state.paceStatus).color)
                }
                if let hr = state.heartRate {
                    Spacer()
                    metric("HR") { Text("\(hr)") }
                }
            }
            if state.target != nil || state.step != nil {
                HStack(spacing: 6) {
                    let style = PaceStatusStyle(state.paceStatus)
                    if let symbol = style.symbol {
                        Image(systemName: symbol).foregroundStyle(style.color)
                    }
                    if let label = style.label {
                        Text(label).font(.caption.weight(.semibold)).foregroundStyle(KXColor.ink)
                    }
                    if let target = state.target {
                        Text("Target \(target)").font(.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    if let step = state.step {
                        Text(step + (state.stepDetail.map { " · \($0)" } ?? ""))
                            .font(.caption.weight(.semibold)).foregroundStyle(KXColor.ink).lineLimit(1)
                    }
                }
            }
        }
    }

    private var strengthBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                metric(state.mode == .resting ? "Rest" : "Time") { WorkoutClock(state: state) }
                Spacer()
                metric("Sets") { Text("\(state.setsDone ?? 0)/\(state.setsTotal ?? 0)") }
            }
            if let next = state.nextSet {
                Text("Next: \(next)").font(.caption.weight(.semibold)).foregroundStyle(KXColor.ink).lineLimit(1)
            }
        }
    }

    private func metric<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(KXColor.inkSecondary)
            value().font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(KXColor.ink)
        }
    }
}

/// A run shows a runner; the gym shows the Kinetix mark.
struct WorkoutKindIcon: View {
    let kind: String
    var size: CGFloat = 16

    var body: some View {
        if kind == "run" {
            Image(systemName: "figure.run")
        } else {
            Image("KinetixMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("Kinetix")
        }
    }
}
