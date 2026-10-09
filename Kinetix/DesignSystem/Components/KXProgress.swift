import SwiftUI

/// Thin rounded progress bar.
struct KXProgressBar: View {
    var value: Double // 0...1
    var tint: Color = KXColor.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(KXColor.border)
                Capsule().fill(tint)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

/// Ring gauge used for readiness ("92% Optimized").
struct KXRingGauge: View {
    var value: Double // 0...1
    var label: String
    var caption: String?
    var tint: Color = KXColor.accent
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(KXColor.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label)
                    .font(KXFont.metricSmall)
                    .foregroundStyle(KXColor.ink)
                if let caption {
                    Text(caption)
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, caption].compactMap { $0 }.joined(separator: " "))
    }
}

/// Onboarding header: back button, "Step 2 of 4" and a segmented progress bar.
struct KXStepProgress: View {
    let step: Int
    let total: Int
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            if let onBack {
                KXIconButton(systemImage: "chevron.left", accessibilityLabel: "Back", size: 36, action: onBack)
            }
            Text("Step \(step) of \(total)")
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.ink)
            HStack(spacing: KXSpacing.xs) {
                ForEach(1...max(total, 1), id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? KXColor.accent : KXColor.surfaceTint)
                        .frame(height: 6)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Status label: a coloured icon plus ink text (status is never colour alone, and
/// light status colours aren't legible as text).
struct KXStatusPill: View {
    enum Level { case low, optimal, high, neutral }

    let level: Level
    let text: String

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(text).font(KXFont.captionEmphasis).foregroundStyle(KXColor.ink)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.xs + 2)
        .background(color.opacity(0.14), in: Capsule())
    }

    private var symbol: String {
        switch level {
        case .low: return "arrow.down.circle.fill"
        case .optimal: return "checkmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .neutral: return "hourglass.circle.fill"
        }
    }

    private var color: Color {
        switch level {
        case .low: return KXColor.warning
        case .optimal: return KXColor.success
        case .high: return KXColor.danger
        case .neutral: return KXColor.slate
        }
    }
}

/// A value against a target: fill in the series colour, track a lighter step of it.
struct KXMeter: View {
    let label: String
    let valueText: String
    let targetText: String?
    /// 0...1 (values above 1 show a full bar).
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                Spacer()
                Text(valueText).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                if let targetText {
                    Text("/ \(targetText)").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color).frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([valueText, targetText.map { "of \($0)" }].compactMap { $0 }.joined(separator: " "))
    }
}
