import SwiftUI
import TrainingEngine

/// During a run: controls (swipe right), the main page and, for structured runs, the whole
/// run (swipe left). Structured runs open on the current rep: pace against its target and
/// how much of it is left. Free runs open on the whole-run numbers.
struct RunLiveView: View {
    @State private var workout = RunWorkoutManager.shared
    @State private var page = 1
    @State private var confirmEnd = false
    // Crown gesture: a firm turn in one go triggers the crown's action.
    @State private var crownValue = 0.0
    @State private var lastCrownValue = 0.0
    @State private var crownTurned = 0.0
    @State private var crownLocked = false
    @FocusState private var crownFocused: Bool

    /// Crown value per full turn at `.medium` sensitivity. A best estimate: if a quarter turn
    /// feels too light or too stiff on a real watch, change this.
    private static let crownUnitsPerTurn = 2.0

    private var format: DisplayFormat { DisplayFormat(units: workout.units) }
    private var isStructured: Bool { workout.isStructured }

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
        .focusable()
        .focused($crownFocused)
        .focusEffectDisabled()
        .digitalCrownRotation($crownValue, from: -1_000_000, through: 1_000_000, by: nil, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: false,
                              onChange: { _ in }, onIdle: { crownIdle() })
        .onChange(of: crownValue) { _, value in crownMoved(to: value) }
        .onAppear { crownFocused = true }
        .overlay { crownRing }
        .overlay(alignment: .bottom) { gestureBar }
        .animation(.easeInOut(duration: 0.2), value: workout.undoBanner)
        .confirmationDialog(workout.isMirroring ? "Finish this run?" : "End this run?", isPresented: $confirmEnd) {
            Button(workout.isMirroring ? "Finish run" : "End run") { Task { await workout.end() } }
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
                    Text("\(segment.paceIsGuide == true ? "effort ~" : "target ")\(Units.formatPace(target.fastest, units: workout.units))–\(Units.formatPace(target.slowest, units: workout.units))\(Units.paceUnitLabel(workout.units))")
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
            HStack {
                heartRate(snapshot)
                Spacer()
                if let lap = snapshot?.lapNumber {
                    Text("Lap \(lap) · \(Units.formatMinutesSeconds(snapshot?.lapElapsedSeconds ?? 0))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.teal)
                }
            }
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
        if workout.isPhoneLinkStale {
            Label("Waiting for iPhone…", systemImage: "iphone.slash").font(.caption2).foregroundStyle(WatchColor.offPace)
        } else if workout.isPaused {
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
                controlButton(workout.nextOrLapLabel, symbol: workout.nextOrLapLabel == "Lap" ? "flag.fill" : "forward.end.fill",
                              tint: .teal) {
                    workout.nextOrLap()
                    page = 1
                }
                if !workout.isMirroring {
                    // On a mirrored run the iPhone does the talking.
                    controlButton(workout.voiceEnabled ? "Voice on" : "Voice off",
                                  symbol: workout.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", tint: .gray) {
                        workout.voiceEnabled.toggle()
                    }
                }
            }
        }
    }

    // MARK: Gestures

    private var crownThreshold: Double { max(workout.controls.crownTurn, 0.1) * Self.crownUnitsPerTurn }
    private var crownProgress: Double { min(abs(crownTurned) / crownThreshold, 1) }

    /// Adds up a turn in one direction; reversing starts again. Reaching the threshold runs
    /// the crown's action once, then the crown must stop before it can trigger again.
    private func crownMoved(to value: Double) {
        let delta = value - lastCrownValue
        lastCrownValue = value
        guard workout.controls.crown != .off, workout.phase == .running, !crownLocked, delta != 0 else { return }
        crownTurned = (crownTurned == 0 || (crownTurned > 0) == (delta > 0)) ? crownTurned + delta : delta
        if abs(crownTurned) >= crownThreshold {
            crownLocked = true
            crownTurned = 0
            workout.perform(workout.controls.crown)
        }
    }

    private func crownIdle() {
        crownTurned = 0
        crownLocked = false
    }

    /// Fills as the crown turns, so it's clear how far to go.
    @ViewBuilder
    private var crownRing: some View {
        if crownProgress > 0.15 {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: crownProgress)
                    .stroke(WatchColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol(for: workout.controls.crown)).font(.title2)
            }
            .frame(width: 70, height: 70)
            .padding(8)
            .background(.black.opacity(0.75), in: Circle())
            .allowsHitTesting(false)
        }
    }

    /// The Undo banner after a skip, lap or pause; otherwise the double tap button.
    @ViewBuilder
    private var gestureBar: some View {
        if let banner = workout.undoBanner {
            HStack(spacing: 6) {
                Text(banner.text).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Button("Undo") { workout.undo() }
                    .font(.caption2.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(WatchColor.accent)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.85), in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if WatchStore.supportsDoubleTap, workout.controls.doubleTap != .off {
            HStack {
                Spacer()
                Button {
                    workout.perform(workout.controls.doubleTap)
                } label: {
                    Image(systemName: symbol(for: workout.controls.doubleTap)).font(.footnote.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.teal.opacity(0.35), in: Circle())
                .doubleTapShortcut()
                .accessibilityLabel(workout.controls.doubleTap == .pauseResume ? (workout.isPaused ? "Resume" : "Pause") : workout.nextOrLapLabel)
            }
        }
    }

    private func symbol(for action: WatchControlSettings.Action) -> String {
        switch action {
        case .off: return "circle"
        case .pauseResume: return workout.isPaused ? "play.fill" : "pause.fill"
        case .nextOrLap: return workout.nextOrLapLabel == "Lap" ? "flag.fill" : "forward.end.fill"
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

private extension View {
    /// Makes this button the one double tap (finger and thumb) presses, on watchOS 11+.
    @ViewBuilder
    func doubleTapShortcut() -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
