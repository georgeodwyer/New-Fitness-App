import SwiftUI
import UIKit
import SwiftData

@main
struct KinetixApp: App {
    private let container: ModelContainer
    private let launch = LaunchOptions()

    init() {
        KXFont.configureNavigationBars()
        do {
            container = try Persistence.makeContainer(inMemory: launch.isUITesting)
        } catch {
            // A broken store is unrecoverable at launch; surface it loudly in development.
            fatalError("Could not open the Kinetix database: \(error)")
        }
        let appContainer = self.container
        MainActor.assumeIsolated {
            SyncService.shared.configure(container: appContainer)
            if !LaunchOptions().isUITesting {
                WatchSyncService.shared.configure(container: appContainer)
                WatchMirrorService.shared.configure()
                GarminService.shared.configure(container: appContainer)
            }
        }
        if launch.seedSample {
            MainActor.assumeIsolated {
                SampleData.seed(into: container.mainContext, weeksToRace: launch.seedWeeks)
                if launch.seedHistory {
                    SampleData.seedHistory(into: container.mainContext)
                    HealthService.shared.loadSample()
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(AppearanceModifier(forceDark: launch.forceDark))
        }
        .modelContainer(container)
    }
}

/// Launch arguments used by the automated screenshot tests.
struct LaunchOptions {
    private let arguments = ProcessInfo.processInfo.arguments

    /// Fresh in-memory database, so tests never touch real data.
    var isUITesting: Bool { arguments.contains("-ui-testing") }
    /// Start with the sample profile and plan.
    var seedSample: Bool { isUITesting && arguments.contains("-seed-sample") }
    /// Also add four weeks of past training (dashboard screenshots).
    var seedHistory: Bool { isUITesting && arguments.contains("-seed-history") }
    /// Weeks until the sample race (default 12), e.g. `-seed-weeks 40` for a long plan.
    var seedWeeks: Int? {
        guard isUITesting, let i = arguments.firstIndex(of: "-seed-weeks"), i + 1 < arguments.count else { return nil }
        return Int(arguments[i + 1])
    }
    var forceDark: Bool { isUITesting && arguments.contains("-dark") }
}

/// Light / dark / follow the system. A per-phone choice (Settings → Appearance).
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"
    /// Dark until someone picks otherwise in Settings.
    static let defaultChoice = AppearanceChoice.dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct AppearanceModifier: ViewModifier {
    let forceDark: Bool
    @AppStorage(AppearanceChoice.storageKey) private var appearance = AppearanceChoice.defaultChoice.rawValue

    func body(content: Content) -> some View {
        content
            .font(KXFont.body)
            .preferredColorScheme(forceDark ? .dark : (AppearanceChoice(rawValue: appearance) ?? .defaultChoice).colorScheme)
    }
}

extension KXFont {
    /// Navigation bars use the same faces as the screens.
    static func configureNavigationBars() {
        let titleSize = UIFontMetrics(forTextStyle: .headline).scaledValue(for: 20)
        let largeSize = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: 34)
        let appearance = UINavigationBar.appearance()
        if let font = UIFont(name: KXFont.Face.condensedBold.rawValue, size: titleSize) {
            appearance.titleTextAttributes = [.font: font]
        }
        if let font = UIFont(name: KXFont.Face.condensedBold.rawValue, size: largeSize) {
            appearance.largeTitleTextAttributes = [.font: font]
        }
    }
}
