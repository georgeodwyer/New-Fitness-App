import SwiftUI
import UIKit

/// Kinetix colour tokens, taken from the Stitch designs (light mint surfaces,
/// warm orange accent, charcoal ink). Each token has a dark-mode variant.
/// Values are approximations from the overview screenshot; replace them with the
/// exact hex values from the Stitch export when available — every screen updates.
enum KXColor {
    // Surfaces
    static let background = dynamic(light: 0xF2F7F5, dark: 0x0E1513)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x18211E)
    static let surfaceTint = dynamic(light: 0xE4F1ED, dark: 0x1F2B27)
    static let border = dynamic(light: 0xDFE9E5, dark: 0x2A3733)

    // Ink (text and icons)
    static let ink = dynamic(light: 0x13201C, dark: 0xEEF4F2)
    static let inkSecondary = dynamic(light: 0x5A6B66, dark: 0xA7B5B1)
    static let inkTertiary = dynamic(light: 0x93A39F, dark: 0x6F7F7A)
    static let inverted = dynamic(light: 0x1B2521, dark: 0xEEF4F2)
    static let onInverted = dynamic(light: 0xFFFFFF, dark: 0x13201C)

    // Brand accent
    static let accent = dynamic(light: 0xF47B20, dark: 0xFF8D3A)
    static let accentSoft = dynamic(light: 0xFDE9D8, dark: 0x3A2616)
    static let onAccent = Color.white

    // Data and status
    static let teal = dynamic(light: 0x4FB3A2, dark: 0x5CC7B5)
    static let slate = dynamic(light: 0x6F8A92, dark: 0x8BA3AA)

    /// Discipline colours for charts, meters and session icons. Validated as a pair
    /// (lightness band, chroma, colour-blind separation, contrast) in light and dark.
    static let run = dynamic(light: 0xDD6A12, dark: 0xDE7024)
    static let lift = dynamic(light: 0x008E80, dark: 0x2A9D8F)
    /// De-emphasis for "other" data (cross-training, mobility).
    static let other = dynamic(light: 0xA3B1AD, dark: 0x5E6D69)

    /// Status colours: reserved meaning, always shown with an icon and a label.
    static let success = Color(UIColor(hex: 0x0CA30C))
    static let warning = Color(UIColor(hex: 0xFAB219))
    static let danger = Color(UIColor(hex: 0xD03B3B))

    /// Ordinal ramp for training phases (base → taper), one hue, light → dark.
    static func phase(_ index: Int) -> Color {
        let light: [UInt32] = [0xF0A266, 0xE5802F, 0xC55F0E, 0x8E440A]
        let dark: [UInt32] = [0x8A440E, 0xB85B10, 0xE07A2A, 0xF2A86A]
        let i = min(max(index, 0), 3)
        return dynamic(light: light[i], dark: dark[i])
    }

    static let strength = lift

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
