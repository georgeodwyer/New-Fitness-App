import SwiftUI
import TrainingEngine

/// Today's planned runs, a free run, saved workouts and the next few days.
struct RunListView: View {
    @State private var store = WatchStore.shared
    @State private var workout = RunWorkoutManager.shared

    private var calendar: Calendar { .current }
    private var plan: WatchPlan { store.plan }

    var body: some View {
        NavigationStack {
            List {
                if let notice = workout.notice {
                    Section {
                        Label(notice, systemImage: "iphone").font(.footnote)
                        Button("OK") { workout.clearNotice() }
                    }
                }
                // Closed the watch app mid-session: pick the phone's workout back up (heart rate too).
                Section {
                    Button {
                        workout.joinPhoneWorkout()
                    } label: {
                        Label(workout.isLookingForPhoneWorkout ? "Looking…" : "Join iPhone workout", systemImage: "iphone.radiowaves.left.and.right")
                            .font(.footnote)
                    }
                    .disabled(workout.isLookingForPhoneWorkout)
                }
                let today = plan.planned(on: .now, calendar: calendar)
                if !today.isEmpty {
                    Section {
                        ForEach(today) { option in row(option, highlight: true) }
                    } header: {
                        WatchOverline("Today · planned")
                    }
                }
                Section {
                    row(.freeRun)
                }
                if !plan.templates.isEmpty {
                    Section("My workouts") {
                        ForEach(plan.templates) { option in row(option) }
                    }
                }
                let upcoming = Array(plan.upcoming(after: .now, calendar: calendar).prefix(6))
                if !upcoming.isEmpty {
                    Section("Coming up") {
                        ForEach(upcoming) { option in row(option) }
                    }
                }
                Section {
                    if !store.hasPlan {
                        Text("Open Kinetix on your iPhone to send your plan and workouts to your watch.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Plan updated \(plan.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if store.pendingResults > 0 {
                        Label("\(store.pendingResults) run\(store.pendingResults == 1 ? "" : "s") waiting for your iPhone",
                              systemImage: "iphone.and.arrow.forward")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle { Text("KINETIX").font(WatchFont.title(16)).foregroundStyle(WatchColor.accent) }
            .navigationDestination(for: WatchRunOption.self) { option in
                RunReadyView(option: option)
            }
        }
        .task { await workout.requestAuthorization() }
    }

    private func row(_ option: WatchRunOption, highlight: Bool = false) -> some View {
        NavigationLink(value: option) {
            VStack(alignment: .leading, spacing: 3) {
                if let date = option.date, !calendar.isDateInToday(date) {
                    WatchOverline(date.formatted(.dateTime.weekday(.abbreviated)), color: WatchColor.accent)
                }
                Text(option.title.uppercased()).font(WatchFont.title(highlight ? 20 : 17)).lineLimit(2)
                if !option.detail.isEmpty {
                    Text(option.detail).font(.caption2).foregroundStyle(WatchColor.inkSecondary).lineLimit(2)
                }
                if let segments = option.structure?.segments, segments.count > 1 {
                    StructureBar(segments: segments)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 16)
                .fill(highlight
                      ? AnyShapeStyle(LinearGradient(colors: [WatchColor.run.opacity(0.3), WatchColor.surface],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(WatchColor.surface))
        )
    }
}

/// The run's shape: one block per step, work steps in run blue.
struct StructureBar: View {
    let segments: [RunSegment]

    var body: some View {
        GeometryReader { proxy in
            let weights = segments.map(Self.weight)
            let total = max(weights.reduce(0, +), 1)
            let gap: CGFloat = 2
            let width = proxy.size.width - gap * CGFloat(segments.count - 1)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.kind == .work ? WatchColor.run : Color.white.opacity(0.22))
                        .frame(width: max(width * CGFloat(weights[index] / total), 2))
                }
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }

    /// Roughly how long a step takes, so the blocks are in proportion.
    private static func weight(_ segment: RunSegment) -> Double {
        switch segment.length {
        case .distance(let meters): return meters / 1000 * 300
        case .duration(let seconds): return seconds
        }
    }
}

extension WatchRunOption: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The steps of a run, and Start.
struct RunReadyView: View {
    let option: WatchRunOption
    @State private var workout = RunWorkoutManager.shared

    private var format: DisplayFormat { DisplayFormat(units: workout.units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(option.title.uppercased()).font(WatchFont.title(20))
                if let segments = option.structure?.segments, segments.count > 1 {
                    StructureBar(segments: segments)
                }
                if let segments = option.structure?.segments, !segments.isEmpty {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        HStack(alignment: .firstTextBaseline) {
                            Circle().fill(segment.kind == .work ? WatchColor.run : WatchColor.inkSecondary).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(segment.label ?? segment.kind.displayName) · \(format.segmentLength(segment.length))")
                                    .font(.caption)
                                if let target = segment.targetPace {
                                    Text(format.paceRange(target)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text(option.detail.isEmpty ? "Run at your own pace. You'll hear your splits." : option.detail)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Voice cues", isOn: Binding(get: { workout.voiceEnabled }, set: { workout.voiceEnabled = $0 }))
                    .font(.caption)
                Button {
                    Task { await workout.start(option) }
                } label: {
                    Label(workout.phase == .starting ? "Starting…" : "Start", systemImage: "play.fill")
                }
                .buttonStyle(WatchFilledButtonStyle())
                .disabled(workout.phase == .starting)
                if let error = workout.errorText {
                    Text(error).font(.caption2).foregroundStyle(WatchColor.offPace)
                }
            }
        }
        .navigationTitle("Run")
    }
}
