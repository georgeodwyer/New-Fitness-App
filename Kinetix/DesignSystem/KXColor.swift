import SwiftUI
import UIKit

/// Kinetix colour tokens. Dark ("Volt") is the default look: near-black surfaces, a lime
/// accent, cyan for running and pink for the gym. Light ("warm stone") uses stone and
/// ivory surfaces; there the accent is black and lime sits on it (lime text on white
/// can't be read), and the data colours are a shade deeper.
enum KXColor {
    // Surfaces
    static let background = dynamic(light: 0xE7E3DA, dark: 0x050506)
    static let surface = dynamic(light: 0xF7F4EE, dark: 0x111113)
    static let surfaceTint = dynamic(light: 0xEDE9E1, dark: 0x1B1B1E)
    static let border = dynamic(light: 0xDDD8CD, dark: 0x232327)
    /// Soft warm card shadow in light mode; none in dark.
    static let shadow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .clear : UIColor(red: 0.24, green: 0.2, blue: 0.12, alpha: 0.07)
    })

    // Ink (text and icons)
    static let ink = dynamic(light: 0x15140F, dark: 0xF4F5F1)
    static let inkSecondary = dynamic(light: 0x5F5B52, dark: 0xA2A59F)
    static let inkTertiary = dynamic(light: 0x9D988C, dark: 0x666963)
    static let inverted = dynamic(light: 0x15140F, dark: 0xF4F5F1)
    static let onInverted = dynamic(light: 0xF7F4EE, dark: 0x0A0B05)

    // Brand accent: lime in dark, black (with lime on it) in light.
    static let accent = dynamic(light: 0x111210, dark: 0xD6FF3D)
    static let accentSoft = dynamic(light: 0xE2DED3, dark: 0x22280E)
    static let onAccent = dynamic(light: 0xD6FF3D, dark: 0x0A0B05)

    // Data and status
    static let teal = dynamic(light: 0x13B26A, dark: 0x36E27E)
    static let slate = dynamic(light: 0x7C8A90, dark: 0x8A979C)

    /// Discipline colours for charts, meters and session icons.
    static let run = dynamic(light: 0x0093D1, dark: 0x3BD3FF)
    static let lift = dynamic(light: 0xDE3F86, dark: 0xFF5FA2)
    /// De-emphasis for "other" data (cross-training, mobility).
    static let other = dynamic(light: 0xB4AEA2, dark: 0x5C6B73)
    /// Marks a day with two sessions.
    static let doubleSession = lift

    /// Status colours: reserved meaning, always shown with an icon and a label. Also the
    /// recovery scale (good, fair, low).
    static let success = dynamic(light: 0x13B26A, dark: 0x36E27E)
    static let warning = dynamic(light: 0xE39A0B, dark: 0xFFC23D)
    static let danger = dynamic(light: 0xE5484D, dark: 0xFF4F4F)

    /// Ordinal ramp for training phases (base → taper), one hue, light → dark.
    static func phase(_ index: Int) -> Color {
        let light: [UInt32] = [0x9FD3EA, 0x4FB3DE, 0x0093D1, 0x006A99]
        let dark: [UInt32] = [0x1E5A70, 0x2A93B5, 0x3BD3FF, 0x9BE8FF]
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
