import SwiftUI
import TrainingEngine

/// During a run: controls (swipe right), the main page and, for structured runs, the whole
/// run (swipe left). Structured runs open on the current rep: pace against its target and
/// how much of it is left. Free runs open on the whole-run numbers.
struct RunLiveView: View {
    @State private var workout = RunWorkoutManager.shared
    @State private var page = 1
    @State private var confirmEnd = false

    private var format: DisplayFormat { DisplayFormat(units: workout.units) }
    private var isStructured: Bool { workout.option?.structure != nil }

    var body: some View {
        TabView(selection: $page) {
            controls.tag(0)
            if isStructured {
                repPage.tag(1)
                wholeRunPage.tag(2)
            } else {
                wholeRunPage.tag(1)
            }
        }
        .tabViewStyle(.page)
        .confirmationDialog("End this run?", isPresented: $confirmEnd) {
            Button("End run") { Task { await workout.end() } }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: Current rep (main page for structured runs)

    private var repPage: some View {
        let snapshot = workout.snapshot
        return VStack(alignment: .leading, spacing: 1) {
            if let segment = snapshot?.segment {
                HStack(alignment: .firstTextBaseline) {
                    Text(segment.label ?? segment.kind.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(segment.kind == .work ? WatchColor.accent : .teal)
                        .lineLimit(1)
                    Spacer()
                    if let remaining = snapshot?.segmentRemaining {
                        Text("\(format.segmentLength(remaining)) left")
                            .font(.system(.footnote, design: .rounded).monospacedDigit().weight(.semibold))
                    }
                }
                ProgressView(value: snapshot?.segmentProgress ?? 0)
                    .tint(segment.kind == .work ? WatchColor.accent : .teal)
                paceLine(snapshot)
                if let target = segment.targetPace {
                    Text("target \(Units.formatPace(target.fastest, units: workout.units))–\(Units.formatPace(target.slowest, units: workout.units))\(Units.paceUnitLabel(workout.units))")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(Units.paceUnitLabel(workout.units)).font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    heartRate(snapshot)
                    Spacer()
                    if let next = snapshot?.nextSegment {
                        Text("Next: \(next.label ?? next.kind.displayName)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                Text(snapshot?.isStructureComplete == true ? "Workout complete" : "Starting…").font(.headline)
                paceLine(snapshot)
                Text("Keep running or end when you're ready.").font(.caption2).foregroundStyle(.secondary)
            }
            status(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Whole run

    private var wholeRunPage: some View {
        let snapshot = workout.snapshot
        return VStack(alignment: .leading, spacing: 2) {
            Text(Units.formatMinutesSeconds(snapshot?.elapsedSeconds ?? 0))
                .font(.system(.title3, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchColor.accent)
            Text(format.distance(snapshot?.distanceMeters ?? 0, decimals: 2))
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if isStructured {
                // The rep page has the live pace; here the whole run's average.
                Text("\(snapshot?.averagePace.map { Units.formatPace($0, units: workout.units) } ?? "–:––")\(Units.paceUnitLabel(workout.units)) avg")
                    .font(.system(.title3, design: .rounded).monospacedDigit())
            } else {
                paceLine(snapshot)
                Text("\(snapshot?.averagePace.map { Units.formatPace($0, units: workout.units) } ?? "–:––")\(Units.paceUnitLabel(workout.units)) avg")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            heartRate(snapshot)
            status(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Pieces

    private func paceLine(_ snapshot: RunSnapshot?) -> some View {
        Text(snapshot?.currentPace.map { Units.formatPace($0, units: workout.units) } ?? "–:––")
            .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(WatchColor.pace(snapshot?.paceStatus))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private func heartRate(_ snapshot: RunSnapshot?) -> some View {
        Label(snapshot?.heartRate.map { "\(Int($0.rounded()))" } ?? "--", systemImage: "heart.fill")
            .font(.system(.body, design: .rounded).monospacedDigit())
            .foregroundStyle(WatchColor.heart)
    }

    @ViewBuilder
    private func status(_ snapshot: RunSnapshot?) -> some View {
        if workout.isPaused {
            Text("Paused").font(.caption).foregroundStyle(WatchColor.offPace)
        } else if snapshot?.gpsAvailable == false {
            Text("Finding GPS…").font(.caption2).foregroundStyle(.secondary)
        }
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
                        page = 1
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
