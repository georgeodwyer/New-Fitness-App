import SwiftUI
import TrainingEngine

/// A gym session from the iPhone: what's next, heart rate coloured by zone, the set or rest
/// timer, and Start set / Finish set (also on double tap and the crown). Swipe right for End.
struct GymLiveView: View {
    @State private var workout = RunWorkoutManager.shared
    @State private var page = 1
    @State private var confirmEnd = false
    // Crown: a firm turn in one go starts or finishes a set (same feel as on runs).
    @State private var crownValue = 0.0
    @State private var lastCrownValue = 0.0
    @State private var crownTurned = 0.0
    @State private var crownLocked = false
    @State private var lastCrownMove = Date.distantPast
    /// When the current turn began: it must reach the threshold within the sensitivity's window.
    @State private var crownStartedAt = Date.distantPast
    @FocusState private var crownFocused: Bool

    /// Crown value per full turn at `.medium` sensitivity (matches the run screen).
    private static let crownUnitsPerTurn = 2.0

    private static let zoneColors: [Color] = [.gray, .teal, .green, .orange, .red]

    var body: some View {
        TabView(selection: $page) {
            controls.tag(0)
            main.tag(1)
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
        .confirmationDialog("Stop showing this session?", isPresented: $confirmEnd) {
            Button("Stop showing") { Task { await workout.end() } }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your iPhone keeps recording it.")
        }
    }

    private var frame: GymMirrorFrame? { workout.gymFrame }

    // MARK: Crown

    private var crownEnabled: Bool { workout.controls.crown != .off && frame.map { !$0.isComplete } ?? false }
    private var crownThreshold: Double { workout.controls.crownTurnsNeeded * Self.crownUnitsPerTurn }
    private var crownProgress: Double { min(abs(crownTurned) / crownThreshold, 1) }

    private func crownMoved(to value: Double) {
        let delta = value - lastCrownValue
        lastCrownValue = value
        let now = Date()
        if now.timeIntervalSince(lastCrownMove) > 0.4 { crownIdle() }
        lastCrownMove = now
        scheduleRingReset(after: now)
        guard crownEnabled, !crownLocked, delta != 0 else { return }
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
            workout.gymPrimary()
        }
    }

    private func crownIdle() {
        crownTurned = 0
        crownLocked = false
    }

    private func scheduleRingReset(after moment: Date) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if lastCrownMove == moment { crownIdle() }
        }
    }

    @ViewBuilder
    private var crownRing: some View {
        if crownProgress > 0.15 {
            let starting = frame?.setStartedAt == nil
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: crownProgress)
                    .stroke(starting ? WatchColor.accent : .green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: starting ? "play.fill" : "checkmark").font(.title2)
            }
            .frame(width: 70, height: 70)
            .padding(8)
            .background(.black.opacity(0.75), in: Circle())
            .allowsHitTesting(false)
        }
    }

    private var main: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 3) {
                Text(frame?.isComplete == true ? "All sets done" : (frame?.exercise ?? "Waiting for iPhone…"))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let setText = frame?.setText, frame?.isComplete != true {
                    Text(setText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                heartRate
                timer(at: context.date)
                Spacer(minLength: 0)
                if let frame, !frame.isComplete {
                    let starting = frame.setStartedAt == nil
                    Button {
                        workout.gymPrimary()
                    } label: {
                        Label(starting ? "Start set" : "Finish set", systemImage: starting ? "play.fill" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(starting ? WatchColor.accent : .green)
                    .modifier(PrimaryDoubleTap())
                }
                if workout.isPhoneLinkStale {
                    Label("Waiting for iPhone…", systemImage: "iphone.slash").font(.caption2).foregroundStyle(WatchColor.offPace)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var heartRate: some View {
        let bpm = workout.liveHeartRate
        let zone = bpm.flatMap { value in frame.map { $0.zone(for: value) } } ?? 0
        let color = zone > 0 ? Self.zoneColors[zone - 1] : WatchColor.heart
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "heart.fill").foregroundStyle(color)
            Text(bpm.map { "\(Int($0.rounded()))" } ?? "--")
                .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
            if zone > 0 {
                Text("Z\(zone)").font(.caption.weight(.bold)).foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func timer(at now: Date) -> some View {
        if let started = frame?.setStartedAt {
            Text("Set \(Units.formatMinutesSeconds(now.timeIntervalSince(started)))")
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.green)
        } else if let rest = frame?.restEndsAt, rest > now {
            Text("Rest \(Units.formatMinutesSeconds(rest.timeIntervalSince(now)))")
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(WatchColor.offPace)
        } else if let frame, !frame.isComplete {
            Text("\(frame.setsDone) of \(frame.setsTotal) sets").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                confirmEnd = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "xmark").font(.title3)
                    Text("End").font(.caption2)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .tint(.red)
            Text("Finish the session on your iPhone.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Double tap (finger and thumb) presses Start set / Finish set, on watchOS 11+.
private struct PrimaryDoubleTap: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.handGestureShortcut(.primaryAction)
        } else {
            content
        }
    }
}
