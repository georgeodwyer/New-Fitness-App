import SwiftUI

/// Spacing scale (points). Use these instead of raw numbers.
enum KXSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Horizontal margin of screen content.
    static let screenMargin: CGFloat = 16
}

enum KXRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

enum KXShadow {
    static let color = Color.black.opacity(0.06)
    static let radius: CGFloat = 12
    static let y: CGFloat = 4
}
