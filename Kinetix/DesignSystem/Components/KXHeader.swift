import SwiftUI

/// Screen header: the Kinetix wordmark top left, the screen title under it, and an
/// optional notification bell.
struct KXScreenHeader: View {
    let title: String
    var onNotifications: (() -> Void)?
    /// Shows a ••• menu with "Edit dashboard" (Today).
    var onEditDashboard: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: KXSpacing.md) {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                KXWordmark(height: 16)
                Text(title)
                    .font(KXFont.title)
                    .foregroundStyle(KXColor.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if let onNotifications {
                KXIconButton(systemImage: "bell", accessibilityLabel: "Plan updates", size: 36, action: onNotifications)
            }
            if let onEditDashboard {
                Menu {
                    Button(action: onEditDashboard) {
                        Label("Edit dashboard", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KXColor.ink)
                        .frame(width: 36, height: 36)
                        .background(KXColor.surface, in: Circle())
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("dashboard.more")
            }
        }
    }
}

/// The KINETIX wordmark: black in light mode, white in dark mode.
struct KXWordmark: View {
    var height: CGFloat = 16
    /// Force a colour (e.g. on share cards over a photo); nil follows light/dark mode.
    var forcedWhite: Bool? = nil

    private var imageName: String {
        switch forcedWhite {
        case true?: return "WordmarkWhite"
        case false?: return "WordmarkBlack"
        case nil: return "Wordmark"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Kinetix")
    }
}

/// The Kinetix "K" mark on its rounded tile (dark tile in light mode, light tile in dark mode).
struct KXLogo: View {
    var size: CGFloat = 32

    var body: some View {
        Image("LogoMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
