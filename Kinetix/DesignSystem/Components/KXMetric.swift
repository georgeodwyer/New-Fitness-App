import SwiftUI

/// A big number with unit and caption: "4:42 /km — Current pace".
struct KXMetric: View {
    enum Size { case large, small }

    let label: String
    let value: String
    var unit: String?
    var detail: String?
    var size: Size = .large

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            KXOverline(label)
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xxs) {
                Text(value)
                    .font(size == .large ? KXFont.metric : KXFont.metricSmall)
                    .foregroundStyle(KXColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            if let detail {
                Text(detail)
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([value, unit, detail].compactMap { $0 }.joined(separator: " "))
    }
}
