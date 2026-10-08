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
        if launch.seedSample {
            MainActor.assumeIsolated { SampleData.seed(into: container.mainContext) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(launch.forceDark ? .dark : nil)
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
    var forceDark: Bool { isUITesting && arguments.contains("-dark") }
}
