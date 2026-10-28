import SwiftUI
import TrainingEngine

/// A gym session from the iPhone: what's next, heart rate coloured by zone, the set or rest
/// timer, and Start set / Finish set (also on double tap and the crown). Swipe right for End.
struct GymLiveView: View {
    @State private var workout = RunWorkoutManager.shared
    @State private var page = 1
    @State private var confirmEnd = false
    /// When the current rest first showed, for the ring's full length.
    @State private var restSeenAt: Date?
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
        .onAppear {
            crownFocused = true
            if frame?.restEndsAt != nil { restSeenAt = Date() }
        }
        .onChange(of: frame?.restEndsAt) { _, _ in restSeenAt = Date() }
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
                    .stroke(starting ? WatchColor.lift : WatchColor.good, style: StrokeStyle(lineWidth: 6, lineCap: .round))
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
                WatchOverline(frame?.title ?? "Gym", color: WatchColor.lift)
                Text((frame?.isComplete == true ? "All sets done" : (frame?.exercise ?? "Waiting for iPhone…")).uppercased())
                    .font(WatchFont.title(20))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let setText = frame?.setText, frame?.isComplete != true {
                    Text(setText).font(.caption2).foregroundStyle(WatchColor.inkSecondary).lineLimit(1)
                }
                if let frame, frame.setsTotal > 0 {
                    setDots(frame)
                }
                if let rest = frame?.restEndsAt, rest > context.date, frame?.setStartedAt == nil {
                    restRing(until: rest, now: context.date)
                } else {
                    heartRate
                    timer(at: context.date)
                }
                Spacer(minLength: 0)
                if let frame, !frame.isComplete {
                    let starting = frame.setStartedAt == nil
                    Button {
                        workout.gymPrimary()
                    } label: {
                        Text(starting ? "Start set" : "Finish set")
                    }
                    .buttonStyle(WatchFilledButtonStyle(color: starting ? WatchColor.lift : WatchColor.good))
                    .modifier(PrimaryDoubleTap())
                }
                if workout.isPhoneLinkStale {
                    Label("Waiting for iPhone…", systemImage: "iphone.slash").font(.caption2).foregroundStyle(WatchColor.warning)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// One bar per set: done, in progress, to do.
    private func setDots(_ frame: GymMirrorFrame) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(frame.setsTotal, 12), id: \.self) { index in
                Capsule()
                    .fill(index < frame.setsDone ? WatchColor.lift
                          : index == frame.setsDone ? WatchColor.lift.opacity(0.4) : WatchColor.surface2)
                    .frame(height: 5)
            }
        }
        .accessibilityLabel("\(frame.setsDone) of \(frame.setsTotal) sets done")
    }

    /// The rest countdown as a ring.
    private func restRing(until end: Date, now: Date) -> some View {
        let left = end.timeIntervalSince(now)
        let total = max(end.timeIntervalSince(restSeenAt ?? now), left, 1)
        return ZStack {
            Circle().stroke(WatchColor.surface2, lineWidth: 8)
            Circle().trim(from: 0, to: left / total)
                .stroke(WatchColor.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Units.formatMinutesSeconds(left)).font(WatchFont.number(30))
                Text("REST").font(WatchFont.unit).tracking(1.2).foregroundStyle(WatchColor.inkSecondary)
            }
        }
        .frame(width: 92, height: 92)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest, \(Int(left)) seconds left")
    }

    private var heartRate: some View {
        let bpm = workout.liveHeartRate
        let zone = bpm.flatMap { value in frame.map { $0.zone(for: value) } } ?? 0
        let color = zone > 0 ? WatchColor.zone(zone) : WatchColor.bad
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(bpm.map { "\(Int($0.rounded()))" } ?? "--").font(WatchFont.number(40)).foregroundStyle(color)
                Text(zone > 0 ? "BPM · Z\(zone)" : "BPM").font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
            }
            if zone > 0 { WatchZoneBar(zone: zone) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func timer(at now: Date) -> some View {
        if let started = frame?.setStartedAt {
            Text("SET \(Units.formatMinutesSeconds(now.timeIntervalSince(started)))")
                .font(WatchFont.title(15)).foregroundStyle(WatchColor.good)
        } else if let frame, !frame.isComplete {
            Text("\(frame.setsDone) OF \(frame.setsTotal) SETS").font(WatchFont.unit).foregroundStyle(WatchColor.inkSecondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                confirmEnd = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(WatchColor.bad, in: Circle())
                    Text("END").font(WatchFont.title(13)).tracking(0.8).foregroundStyle(WatchColor.bad)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(WatchColor.bad.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            Text("Finish the session on your iPhone.").font(.caption2).foregroundStyle(WatchColor.inkSecondary)
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
