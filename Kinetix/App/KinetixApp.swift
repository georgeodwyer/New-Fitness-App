import SwiftUI
import SwiftData

@main
struct KinetixApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            // A broken store is unrecoverable at launch; surface it loudly in development.
            fatalError("Could not open the Kinetix database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
