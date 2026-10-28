import SwiftUI
import TrainingEngine

/// The watch's Volt colours (the phone's dark palette).
enum WatchColor {
    static let accent = hex(0xD6FF3D)
    static let onAccent = hex(0x0A0B05)
    static let run = hex(0x3BD3FF)
    static let lift = hex(0xFF5FA2)
    static let good = hex(0x36E27E)
    static let warning = hex(0xFFC23D)
    static let bad = hex(0xFF4F4F)
    static let surface = hex(0x141416)
    static let surface2 = hex(0x1E1E21)
    static let inkSecondary = hex(0x8C8C93)

    // Older names used around the app.
    static let onPace = good
    static let offPace = warning
    static let heart = bad

    /// Heart-rate zones 1–5.
    static let zones: [Color] = [inkSecondary, run, good, warning, bad]

    static func zone(_ zone: Int) -> Color { zones[min(max(zone, 1), 5) - 1] }

    static func pace(_ status: PaceRange.Position?) -> Color {
        switch status {
        case .onTarget?: return good
        case .tooFast?, .tooSlow?: return warning
        case nil: return .white
        }
    }

    static func tone(_ tone: WatchMetricReading.Tone) -> Color {
        switch tone {
        case .plain: return .white
        case .good: return good
        case .warning: return warning
        case .bad: return bad
        case .zone(let zone): return self.zone(zone)
        }
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// Barlow Condensed for numbers and labels, as on the phone.
enum WatchFont {
    static func number(_ size: CGFloat) -> Font {
        .custom("BarlowCondensed-Bold", size: size).monospacedDigit()
    }

    static func title(_ size: CGFloat = 18) -> Font { .custom("BarlowCondensed-Bold", size: size) }

    /// Small uppercase labels ("PACE", "REP 3 OF 6").
    static let overline = Font.custom("BarlowCondensed-SemiBold", size: 12)
    static let unit = Font.custom("BarlowCondensed-SemiBold", size: 12)
}

/// "PACE" style label.
struct WatchOverline: View {
    let text: String
    var color: Color = WatchColor.inkSecondary

    init(_ text: String, color: Color = WatchColor.inkSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased()).font(WatchFont.overline).tracking(1.2).foregroundStyle(color).lineLimit(1)
    }
}

/// Five coloured blocks with the current zone lit.
struct WatchZoneBar: View {
    let zone: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(WatchColor.zone(index).opacity(index == zone ? 1 : 0.25))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A full-width filled button: volt (or another colour) with dark text.
struct WatchFilledButtonStyle: ButtonStyle {
    var color: Color = WatchColor.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WatchFont.title(16))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}
