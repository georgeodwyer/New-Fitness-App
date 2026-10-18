import SwiftUI
import TrainingEngine

/// During a run: controls (swipe right), metrics (main page) and the current step.
struct RunLiveView: View {
    @State private var workout = RunWorkoutManager.shared
    @State private var page = 1
    @State private var confirmEnd = false

    private var format: DisplayFormat { DisplayFormat(units: workout.units) }

    var body: some View {
        TabView(selection: $page) {
            controls.tag(0)
            metrics.tag(1)
            if workout.option?.structure != nil { step.tag(2) }
        }
        .tabViewStyle(.page)
        .confirmationDialog("End this run?", isPresented: $confirmEnd) {
            Button("End run") { Task { await workout.end() } }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: Metrics

    private var metrics: some View {
        let snapshot = workout.snapshot
        return VStack(alignment: .leading, spacing: 2) {
            Text(Units.formatMinutesSeconds(snapshot?.elapsedSeconds ?? 0))
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchColor.accent)
            Text(snapshot?.currentPace.map { Units.formatPace($0, units: workout.units) } ?? "–:––")
                .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchColor.pace(snapshot?.paceStatus))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack {
                Text(Units.paceUnitLabel(workout.units)).font(.caption2).foregroundStyle(.secondary)
                if let target = snapshot?.segment?.targetPace {
                    Text("target \(Units.formatPace(target.fastest, units: workout.units))–\(Units.formatPace(target.slowest, units: workout.units))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(format.distance(snapshot?.distanceMeters ?? 0, decimals: 2))
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                Spacer()
                Label(snapshot?.heartRate.map { "\(Int($0.rounded()))" } ?? "--", systemImage: "heart.fill")
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .foregroundStyle(WatchColor.heart)
            }
            if workout.isPaused {
                Text("Paused").font(.caption).foregroundStyle(WatchColor.offPace)
            } else if snapshot?.gpsAvailable == false {
                Text("Finding GPS…").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Current step

    private var step: some View {
        let snapshot = workout.snapshot
        return VStack(alignment: .leading, spacing: 4) {
            if let segment = snapshot?.segment {
                Text(segment.label ?? segment.kind.displayName)
                    .font(.headline).foregroundStyle(segment.kind == .work ? WatchColor.accent : .teal)
                if let remaining = snapshot?.segmentRemaining {
                    Text("\(format.segmentLength(remaining)) left")
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                }
                ProgressView(value: snapshot?.segmentProgress ?? 0)
                    .tint(WatchColor.accent)
                if let target = segment.targetPace {
                    Text(format.paceRange(target)).font(.caption).foregroundStyle(.secondary)
                }
                if let next = snapshot?.nextSegment {
                    Text("Next: \(next.label ?? next.kind.displayName) · \(format.segmentLength(next.length))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            } else if snapshot?.isStructureComplete == true {
                Text("Workout complete").font(.headline)
                Text("Keep running or end when you're ready.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                controlButton(workout.isPaused ? "Resume" : "Pause", symbol: workout.isPaused ? "play.fill" : "pause.fill",
                              tint: WatchColor.offPace) {
                    workout.togglePause()
                    page = 1
                }
                controlButton("End", symbol: "xmark", tint: .red) { confirmEnd = true }
            }
            HStack(spacing: 8) {
                if workout.option?.structure != nil {
                    controlButton("Next step", symbol: "forward.end.fill", tint: .teal) {
                        workout.skipStep()
                        page = 2
                    }
                }
                controlButton(workout.voiceEnabled ? "Voice on" : "Voice off",
                              symbol: workout.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", tint: .gray) {
                    workout.voiceEnabled.toggle()
                }
            }
        }
    }

    private func controlButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .tint(tint)
    }
}

/// After the run: totals and "How hard was that?" (turn the Digital Crown), then save.
struct RunFinishedView: View {
    @State private var workout = RunWorkoutManager.shared
    @State private var effort: Double = 5
    @State private var confirmDiscard = false

    private var format: DisplayFormat { DisplayFormat(units: workout.units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.option?.title ?? "Run").font(.headline)
                if let summary = workout.summary {
                    Text(format.distance(summary.distanceMeters, decimals: 2))
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                    Text(Units.formatMinutesSeconds(summary.durationSeconds))
                        .font(.system(.body, design: .rounded).monospacedDigit())
                    if let pace = summary.averagePace {
                        Text("\(format.pace(pace)) average").font(.caption).foregroundStyle(.secondary)
                    }
                    if let heartRate = summary.averageHeartRate {
                        Label("\(Int(heartRate.rounded())) bpm average", systemImage: "heart.fill")
                            .font(.caption).foregroundStyle(WatchColor.heart)
                    }
                    if let fraction = summary.timeInTargetFraction {
                        Text("\(Int((fraction * 100).rounded()))% on target pace").font(.caption)
                    }
                }
                Divider()
                Text("How hard was that?").font(.headline)
                Text("\(Int(effort)) / 10")
                    .font(.system(.title, design: .rounded).monospacedDigit())
                    .foregroundStyle(WatchColor.accent)
                    .focusable()
                    .digitalCrownRotation($effort, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false,
                                          isHapticFeedbackEnabled: true)
                    .accessibilityLabel("Effort \(Int(effort)) out of 10. Turn the Digital Crown to change.")
                Text("Turn the Digital Crown").font(.caption2).foregroundStyle(.secondary)
                Button {
                    workout.save(effort: effort)
                } label: {
                    Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .tint(WatchColor.accent)
                Button("Discard", role: .destructive) { confirmDiscard = true }
                Text("Saved to Apple Health. It's added to Kinetix next time your iPhone is nearby.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { effort = workout.option?.typicalEffort ?? 5 }
        .confirmationDialog("Discard this run?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { workout.discard() }
            Button("Keep", role: .cancel) {}
        }
    }
}
