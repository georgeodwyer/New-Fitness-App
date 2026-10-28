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
    @State private var lastCrownMove = Date.distantPast
    /// When the current turn began: it must reach the threshold within the sensitivity's window.
    @State private var crownStartedAt = Date.distantPast
    @FocusState private var crownFocused: Bool

    /// Crown value per full turn at `.medium` sensitivity. A best estimate: if a quarter turn
    /// feels too light or too stiff on a real watch, change this.
    private static let crownUnitsPerTurn = 2.0

    private var format: DisplayFormat { DisplayFormat(units: workout.units) }
    private var isStructured: Bool { workout.isStructured }

    var body: some View {
        TabView(selection: $page) {
            controls.tag(0)
            if showsRepPage {
                repPage.tag(1)
            }
            ForEach(Array(screens.enumerated()), id: \.element.id) { index, screen in
                customPage(screen).tag(index + (showsRepPage ? 2 : 1))
            }
        }
        .tabViewStyle(.page)
        .focusable()
        .focused($crownFocused)
        .focusEffectDisabled()
        .digitalCrownRotation($crownValue, from: -1_000_000, through: 1_000_000, by: nil, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: false)
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

    // MARK: Pages

    /// The runner's screens from their phone (the standard set if none are on).
    private var screens: [WatchScreen] {
        let enabled = (WatchStore.shared.plan.screens ?? .standard).enabledScreens
        return enabled.isEmpty ? Array(WatchScreenSettings.standard.enabledScreens.prefix(1)) : enabled
    }

    private var showsRepPage: Bool { isStructured && (WatchStore.shared.plan.screens?.showRepPage ?? true) }

    private var title: String { workout.option?.title ?? "Run" }

    private func customPage(_ screen: WatchScreen) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WatchOverline(title, color: WatchColor.run)
            CustomScreenView(screen: screen, input: workout.metricInputs)
            status(workout.snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Current rep (main page for structured runs)

    private var repPage: some View {
        let snapshot = workout.snapshot
        return VStack(alignment: .leading, spacing: 3) {
            if let segment = snapshot?.segment {
                let isWork = segment.kind == .work
                HStack(alignment: .firstTextBaseline) {
                    WatchOverline(segment.label ?? segment.kind.displayName, color: isWork ? WatchColor.accent : WatchColor.run)
                    Spacer(minLength: 4)
                    if let remaining = snapshot?.segmentRemaining {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(format.segmentLength(remaining)).font(WatchFont.number(17))
                            Text("LEFT").font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                        }
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(WatchColor.surface2)
                        Capsule().fill(isWork ? WatchColor.accent : WatchColor.run)
                            .frame(width: proxy.size.width * min(max(snapshot?.segmentProgress ?? 0, 0), 1))
                    }
                }
                .frame(height: 10)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(snapshot?.currentPace.map { Units.formatPace($0, units: workout.units) } ?? "–:––")
                        .font(WatchFont.number(58))
                        .foregroundStyle(WatchColor.pace(snapshot?.paceStatus))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(Units.paceUnitLabel(workout.units).uppercased()).font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                }
                if let target = segment.targetPace {
                    TargetBand(target: target, pace: snapshot?.currentPace, status: snapshot?.paceStatus,
                               isGuide: segment.paceIsGuide == true, units: workout.units)
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    heartRateReading
                    Spacer(minLength: 4)
                    if let next = snapshot?.nextSegment {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("NEXT").font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                            Text(next.label ?? next.kind.displayName).font(WatchFont.title(13)).lineLimit(1)
                        }
                    }
                }
            } else {
                WatchOverline(snapshot?.isStructureComplete == true ? "Workout complete" : "Starting…", color: WatchColor.accent)
                Text(snapshot?.currentPace.map { Units.formatPace($0, units: workout.units) } ?? "–:––")
                    .font(WatchFont.number(58))
                Text("Keep running or end when you're ready.").font(.caption2).foregroundStyle(WatchColor.inkSecondary)
            }
            status(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    /// "168 BPM · Z4", coloured by zone.
    private var heartRateReading: some View {
        let reading = WatchMetric.heartRate.reading(workout.metricInputs)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(reading.value).font(WatchFont.number(22)).foregroundStyle(WatchColor.tone(reading.tone))
            Text(reading.zone.map { "BPM · Z\($0)" } ?? "BPM").font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
        }
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
        let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            controlButton(workout.isPaused ? "Resume" : "Pause", symbol: workout.isPaused ? "play.fill" : "pause.fill",
                          tint: WatchColor.warning) {
                workout.togglePause()
                page = 1
            }
            controlButton(workout.nextOrLapLabel, symbol: workout.nextOrLapLabel == "Lap" ? "flag.fill" : "forward.end.fill",
                          tint: WatchColor.run) {
                workout.nextOrLap()
                page = 1
            }
            if !workout.isMirroring {
                // On a mirrored run the iPhone does the talking.
                controlButton(workout.voiceEnabled ? "Voice on" : "Voice off",
                              symbol: workout.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", tint: .white) {
                    workout.voiceEnabled.toggle()
                }
            }
            controlButton("End", symbol: "stop.fill", tint: WatchColor.bad) { confirmEnd = true }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Gestures

    private var crownThreshold: Double { workout.controls.crownTurnsNeeded * Self.crownUnitsPerTurn }
    private var crownProgress: Double { min(abs(crownTurned) / crownThreshold, 1) }

    /// Adds up a turn in one direction; reversing starts again. Reaching the threshold runs
    /// the crown's action once, then the crown must stop before it can trigger again.
    private func crownMoved(to value: Double) {
        let delta = value - lastCrownValue
        lastCrownValue = value
        // A pause in turning starts a new gesture (and allows another trigger).
        let now = Date()
        if now.timeIntervalSince(lastCrownMove) > 0.4 { crownIdle() }
        lastCrownMove = now
        scheduleRingReset(after: now)
        guard workout.controls.crown != .off, workout.phase == .running, !crownLocked, delta != 0 else { return }
        let sameWay = crownTurned != 0 && (crownTurned > 0) == (delta > 0)
        if sameWay && now.timeIntervalSince(crownStartedAt) <= workout.controls.crownWindowSeconds {
            crownTurned += delta
        } else {
            // A new turn (or one too slow to count, like a sleeve rubbing): start again.
            crownTurned = delta
            crownStartedAt = now
        }
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

    /// Hides the part-filled ring once the crown has stopped.
    private func scheduleRingReset(after moment: Date) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if lastCrownMove == moment { crownIdle() }
        }
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
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(tint, in: Circle())
                Text(title.uppercased()).font(WatchFont.title(13)).tracking(0.8).foregroundStyle(tint).lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Where the current pace sits against the target range: a band with a marker.
private struct TargetBand: View {
    let target: PaceRange
    let pace: Pace?
    let status: PaceRange.Position?
    let isGuide: Bool
    let units: UnitSystem

    var body: some View {
        let fast = target.fastest.secondsPerKm, slow = target.slowest.secondsPerKm
        let pad = max(slow - fast, 10) * 0.75
        let low = fast - pad, high = slow + pad
        let color = isGuide ? WatchColor.inkSecondary : WatchColor.pace(status)
        VStack(spacing: 1) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = { (value: Double) in CGFloat(min(max((value - low) / (high - low), 0), 1)) * width }
                ZStack(alignment: .leading) {
                    Capsule().fill(WatchColor.surface2).frame(height: 4)
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.3))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
                        .frame(width: x(slow) - x(fast), height: 9)
                        .offset(x: x(fast))
                    if let pace {
                        RoundedRectangle(cornerRadius: 1.5).fill(.white)
                            .frame(width: 3, height: 14)
                            .offset(x: x(pace.secondsPerKm) - 1.5)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            HStack {
                Text(Units.formatPace(target.fastest, units: units))
                Spacer()
                Text(isGuide ? "EFFORT GUIDE" : statusText).foregroundStyle(color)
                Spacer()
                Text(Units.formatPace(target.slowest, units: units))
            }
            .font(WatchFont.unit)
            .foregroundStyle(WatchColor.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target \(Units.formatPace(target.fastest, units: units)) to \(Units.formatPace(target.slowest, units: units)), \(statusText)")
    }

    private var statusText: String {
        switch status {
        case .onTarget?: return "ON TARGET"
        case .tooFast?: return "TOO FAST"
        case .tooSlow?: return "TOO SLOW"
        case nil: return "TARGET"
        }
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
                WatchOverline(workout.option?.title ?? "Run", color: WatchColor.run)
                Label("Run complete", systemImage: "checkmark")
                    .font(WatchFont.overline).foregroundStyle(WatchColor.good).textCase(.uppercase)
                if let summary = workout.summary {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.2f", Units.distance(meters: summary.distanceMeters, in: workout.units)))
                            .font(WatchFont.number(52))
                        Text(Units.distanceUnitLabel(workout.units).uppercased()).font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                        stat("Time", Units.formatMinutesSeconds(summary.durationSeconds))
                        stat("Avg pace", summary.averagePace.map { Units.formatPace($0, units: workout.units) } ?? "–:––")
                        stat("Avg HR", summary.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "–", color: WatchColor.warning)
                        stat("On target", summary.timeInTargetFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "–",
                             color: WatchColor.good)
                    }
                }
                WatchOverline("How hard was that?").padding(.top, 6)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(effort))").font(WatchFont.number(40)).foregroundStyle(WatchColor.accent)
                    Text("/ 10").font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
                }
                .focusable()
                .digitalCrownRotation($effort, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false,
                                      isHapticFeedbackEnabled: true)
                .accessibilityLabel("Effort \(Int(effort)) out of 10. Turn the Digital Crown to change.")
                Text("Turn the Digital Crown").font(.caption2).foregroundStyle(WatchColor.inkSecondary)
                Button("Save") { workout.save(effort: effort) }
                    .buttonStyle(WatchFilledButtonStyle())
                Button("Discard", role: .destructive) { confirmDiscard = true }
                Text("Saved to Apple Health. It's added to Kinetix next time your iPhone is nearby.")
                    .font(.caption2).foregroundStyle(WatchColor.inkSecondary)
            }
        }
        .onAppear { effort = workout.option?.typicalEffort ?? 5 }
        .confirmationDialog("Discard this run?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { workout.discard() }
            Button("Keep", role: .cancel) {}
        }
    }

    private func stat(_ label: String, _ value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WatchOverline(label)
            Text(value).font(WatchFont.number(22)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchColor.surface, in: RoundedRectangle(cornerRadius: 12))
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
