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

/// Traffic-light status for training load.
struct KXStatusPill: View {
    enum Level { case low, optimal, high }

    let level: Level
    let text: String

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(KXFont.captionEmphasis)
        }
        .foregroundStyle(color)
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.xs + 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch level {
        case .low: return KXColor.warning
        case .optimal: return KXColor.success
        case .high: return KXColor.danger
        }
    }
}
