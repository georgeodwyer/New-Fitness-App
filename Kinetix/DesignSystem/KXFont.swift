import SwiftUI

/// Type scale: Barlow Condensed for headings, labels and numbers; Inter for text. Every
/// style is tied to a system text style, so it all scales with Dynamic Type.
/// (Both fonts ship with the app under the SIL Open Font License: docs/licenses.)
enum KXFont {
    enum Face: String {
        case condensedMedium = "BarlowCondensed-Medium"
        case condensedSemiBold = "BarlowCondensed-SemiBold"
        case condensedBold = "BarlowCondensed-Bold"
        case regular = "Inter-Regular"
        case medium = "Inter-Medium"
        case semiBold = "Inter-SemiBold"
        case bold = "Inter-Bold"
    }

    static func custom(_ face: Face, _ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(face.rawValue, size: size, relativeTo: style)
    }

    /// A number in the condensed face at any size: "78", "4:41", "100".
    static func number(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        custom(.condensedBold, size, relativeTo: style).monospacedDigit()
    }

    /// Big screen headline: "Today", "Plan".
    static let display = custom(.condensedBold, 34, relativeTo: .largeTitle)
    /// Screen title in the header bar.
    static let title = custom(.condensedBold, 28, relativeTo: .title2)
    /// Card titles: "Tempo run", "Back squat".
    static let headline = custom(.condensedSemiBold, 20, relativeTo: .headline)
    static let body = custom(.regular, 16, relativeTo: .body)
    static let bodyEmphasis = custom(.semiBold, 16, relativeTo: .body)
    static let callout = custom(.regular, 14, relativeTo: .subheadline)
    static let caption = custom(.regular, 12, relativeTo: .caption)
    static let captionEmphasis = custom(.semiBold, 12, relativeTo: .caption)
    /// Small uppercase labels: "RECOVERY", "THIS WEEK".
    static let overline = custom(.condensedSemiBold, 13, relativeTo: .caption2)
    /// Large live numbers: "4:42", "105.0".
    static let metric = number(40, relativeTo: .largeTitle)
    /// Medium numbers inside tiles: "28.4", "158".
    static let metricSmall = number(26, relativeTo: .title2)

}
