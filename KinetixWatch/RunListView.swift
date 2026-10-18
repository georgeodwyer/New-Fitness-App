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
                let today = plan.planned(on: .now, calendar: calendar)
                if !today.isEmpty {
                    Section("Today") {
                        ForEach(today) { option in row(option) }
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
            .navigationTitle("Kinetix")
            .navigationDestination(for: WatchRunOption.self) { option in
                RunReadyView(option: option)
            }
        }
        .task { await workout.requestAuthorization() }
    }

    private func row(_ option: WatchRunOption) -> some View {
        NavigationLink(value: option) {
            VStack(alignment: .leading, spacing: 2) {
                if let date = option.date, !calendar.isDateInToday(date) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2).foregroundStyle(WatchColor.accent)
                }
                Text(option.title).font(.headline).lineLimit(2)
                if !option.detail.isEmpty {
                    Text(option.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
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
                Text(option.title).font(.headline)
                if let segments = option.structure?.segments, !segments.isEmpty {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        HStack(alignment: .firstTextBaseline) {
                            Circle().fill(segment.kind == .work ? WatchColor.accent : .teal).frame(width: 6, height: 6)
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
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchColor.accent)
                .disabled(workout.phase == .starting)
                if let error = workout.errorText {
                    Text(error).font(.caption2).foregroundStyle(WatchColor.offPace)
                }
            }
        }
        .navigationTitle("Run")
    }
}
