import SwiftUI
import SwiftData

@main
struct KinetixApp: App {
    private let container: ModelContainer
    private let launch = LaunchOptions()

    init() {
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
            }
        }
        if launch.seedSample {
            MainActor.assumeIsolated {
                SampleData.seed(into: container.mainContext)
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
    var forceDark: Bool { isUITesting && arguments.contains("-dark") }
}

/// Light / dark / follow the system. A per-phone choice (Settings → Appearance).
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

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
    @AppStorage(AppearanceChoice.storageKey) private var appearance = AppearanceChoice.system.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(forceDark ? .dark : (AppearanceChoice(rawValue: appearance) ?? .system).colorScheme)
    }
}
