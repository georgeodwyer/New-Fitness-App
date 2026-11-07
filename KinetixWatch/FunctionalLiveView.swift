import SwiftUI
import WatchKit
import TrainingEngine

/// A functional workout from the iPhone: the station, its clock, run pace against target,
/// heart rate and Next (also on double tap). Swipe right for Undo and End.
struct FunctionalLiveView: View {
    @State private var workout = RunWorkoutManager.shared
    @State private var page = 1
    @State private var confirmEnd = false

    private var frame: FunctionalMirrorFrame? { workout.functionalFrame }

    var body: some View {
        TabView(selection: $page) {
            controls.tag(0)
            main.tag(1)
        }
        .tabViewStyle(.page)
        .confirmationDialog("Stop showing this workout?", isPresented: $confirmEnd) {
            Button("Stop showing") { Task { await workout.end() } }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your iPhone keeps recording it.")
        }
    }

    private var main: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    WatchOverline(frame?.progress ?? "Functional", color: WatchColor.warning)
                    Spacer(minLength: 2)
                    heartRate
                }
                if let frame, frame.isFinished {
                    Text("WORKOUT DONE").font(WatchFont.title(20))
                    Text("Save it on your iPhone.").font(.caption2).foregroundStyle(WatchColor.inkSecondary)
                } else if let frame {
                    if let label = frame.phaseLabel {
                        Text(label.uppercased()).font(WatchFont.title(13)).foregroundStyle(WatchColor.good).lineLimit(1)
                    }
                    Text((frame.phaseLabel == nil ? frame.station ?? "" : frame.next ?? "").uppercased())
                        .font(WatchFont.title(20))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if frame.phaseLabel == nil, let detail = frame.detail {
                        Text(detail).font(.caption2).foregroundStyle(WatchColor.inkSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    clock(frame, now: context.date)
                    if let meters = frame.meters {
                        runLine(frame, meters: meters)
                    }
                } else {
                    Text("Waiting for iPhone…").font(WatchFont.title(18))
                }
                Spacer(minLength: 0)
                if let frame, !frame.isFinished {
                    Button {
                        workout.functionalNext()
                    } label: {
                        Text(frame.nextDisabled ? "Wait" : (frame.phaseLabel == "Rest" ? "Skip rest" : (frame.next == nil ? "Finish" : "Next")))
                    }
                    .buttonStyle(WatchFilledButtonStyle(color: WatchColor.accent))
                    .disabled(frame.nextDisabled)
                    .modifier(FunctionalDoubleTap())
                }
                if workout.isPhoneLinkStale {
                    Label("Waiting for iPhone…", systemImage: "iphone.slash").font(.caption2).foregroundStyle(WatchColor.warning)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func clock(_ frame: FunctionalMirrorFrame, now: Date) -> some View {
        if let end = frame.clockEndsAt {
            Text(Units.formatMinutesSeconds(max(0, end.timeIntervalSince(now)))).font(WatchFont.number(34))
        } else if let start = frame.clockStartedAt {
            Text(Units.formatMinutesSeconds(max(0, now.timeIntervalSince(start)))).font(WatchFont.number(34))
        }
    }

    private func runLine(_ frame: FunctionalMirrorFrame, meters: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(meters < 1000 ? "\(Int(meters)) m" : String(format: "%.2f km", meters / 1000))
                .font(WatchFont.number(16))
            Spacer()
            Text(frame.currentPace.map { Units.formatPace($0, units: frame.units) } ?? "–:––")
                .font(WatchFont.number(16))
                .foregroundStyle(WatchColor.pace(frame.pacePosition))
        }
    }

    private var heartRate: some View {
        let bpm = workout.liveHeartRate
        let zone = bpm.flatMap { value in frame.map { $0.zone(for: value) } } ?? 0
        return HStack(spacing: 2) {
            Image(systemName: "heart.fill").font(.system(size: 9))
            Text(bpm.map { "\(Int($0.rounded()))" } ?? "--").font(WatchFont.number(15))
        }
        .foregroundStyle(zone > 0 ? WatchColor.zone(zone) : WatchColor.bad)
        .accessibilityLabel(bpm.map { "Heart rate \(Int($0))" } ?? "No heart rate")
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                workout.functionalUndo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(frame?.canUndo != true)
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
                .frame(maxWidth: .infinity, minHeight: 70)
                .background(WatchColor.bad.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            Text("Finish and save on your iPhone.").font(.caption2).foregroundStyle(WatchColor.inkSecondary)
        }
    }
}

/// Double tap (finger and thumb) presses Next, on watchOS 11+.
private struct FunctionalDoubleTap: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 11.0, *) {
            content.handGestureShortcut(.primaryAction)
        } else {
            content
        }
    }
}
