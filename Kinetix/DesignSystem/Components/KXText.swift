import SwiftUI

/// Tiny uppercase label: "LIVE TELEMETRY HUD".
struct KXOverline: View {
    let text: String
    var color: Color = KXColor.inkSecondary

    init(_ text: String, color: Color = KXColor.inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(KXFont.overline)
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

/// Card section header with optional subtitle and trailing accessory.
struct KXSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(title)
                    .font(KXFont.headline)
                    .foregroundStyle(KXColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            Spacer(minLength: KXSpacing.sm)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

extension KXSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// A headline where part is highlighted in the accent colour:
/// "Calibrate your **Hybrid Engine**".
struct KXAccentHeadline: View {
    let plain: String
    let accented: String

    var body: some View {
        (Text(plain + " ").foregroundStyle(KXColor.ink) + Text(accented).foregroundStyle(KXColor.accent))
            .font(KXFont.display)
    }
}
