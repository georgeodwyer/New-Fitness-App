import SwiftUI
import TrainingEngine

/// A slim bar above the tab bar while a minimised workout keeps running. Tap to reopen it.
struct MiniWorkoutBar: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        if router.isMinimised, let session = router.activeSession {
            Button {
                router.restore()
            } label: {
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: session.kind.discipline == .run ? "figure.run" : "dumbbell.fill")
                        .font(.title3)
                        .foregroundStyle(KXColor.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                        detail
                    }
                    Spacer()
                    Image(systemName: "chevron.up").font(.caption.weight(.semibold)).foregroundStyle(KXColor.inkSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, KXSpacing.lg)
                .padding(.vertical, KXSpacing.sm)
                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.border))
                .shadow(color: KXShadow.color, radius: 8, y: 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, KXSpacing.screenMargin)
            .padding(.bottom, KXSpacing.xs)
            .accessibilityHint("Opens your workout")
            .accessibilityIdentifier("miniWorkout")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let run = router.runModel {
            let snapshot = run.snapshot
            Text("\(Units.formatMinutesSeconds(snapshot.elapsedSeconds)) · \(DisplayFormat(units: run.units).distance(snapshot.distanceMeters, decimals: 2))"
                 + (snapshot.isPaused ? " · Paused" : ""))
                .font(KXFont.caption.monospacedDigit())
                .foregroundStyle(KXColor.inkSecondary)
        } else if let gym = router.strengthModel {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(gymText(gym, now: context.date))
                    .font(KXFont.caption.monospacedDigit())
                    .foregroundStyle(KXColor.inkSecondary)
            }
        } else {
            Text("In progress").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }

    private func gymText(_ gym: StrengthWorkoutModel, now: Date) -> String {
        var text = "\(Units.formatMinutesSeconds(now.timeIntervalSince(gym.log.startedAt))) · \(gym.completedSets)/\(gym.totalSets) sets"
        if let restEnds = gym.restEndsAt {
            let remaining = max(0, restEnds.timeIntervalSince(now))
            text += remaining > 0 ? " · Rest \(Units.formatMinutesSeconds(remaining))" : " · Rest done"
        }
        return text
    }
}
