import SwiftUI
import TrainingEngine

/// Session card from the dashboard's "Today's Schedule":
/// overline, title, detail line and a round orange play button.
struct KXSessionCard: View {
    let overline: String
    let title: String
    let detail: String
    let kind: SessionKind
    var status: SessionStatus = .planned
    var onStart: (() -> Void)?

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(kind.tint)
                .frame(width: 44, height: 44)
                .background(KXColor.surfaceTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                KXOverline(overline, color: KXColor.accent)
                Text(title)
                    .font(KXFont.headline)
                    .foregroundStyle(KXColor.ink)
                Text(detail)
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            Spacer(minLength: KXSpacing.sm)
            switch status {
            case .planned, .swapped:
                if let onStart {
                    KXIconButton(systemImage: "play.fill", accessibilityLabel: "Start \(title)", variant: .accent, size: 44, action: onStart)
                }
            case .completed:
                KXChip(text: "Done", systemImage: "checkmark", variant: .success)
            case .skipped:
                KXChip(text: "Skipped", variant: .outlined)
            }
        }
        .kxCard()
    }
}

extension SessionKind {
    /// Discipline colour: running orange, lifting teal, everything else grey.
    var tint: Color {
        switch discipline {
        case .run: return KXColor.run
        case .strength: return KXColor.lift
        case .crossTraining, .mobility: return KXColor.other
        }
    }

    /// SF Symbol for each session kind.
    var symbolName: String {
        switch self {
        case .run(let type):
            switch type {
            case .intervals, .tempo: return "bolt.heart"
            case .long: return "road.lanes"
            case .easy, .recovery: return "figure.run"
            }
        case .strength: return "dumbbell"
        case .crossTraining: return "bicycle"
        case .mobility: return "figure.flexibility"
        }
    }
}
