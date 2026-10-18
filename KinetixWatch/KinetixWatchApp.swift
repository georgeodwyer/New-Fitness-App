import SwiftUI
import TrainingEngine

@main
struct KinetixWatchApp: App {
    @State private var store = WatchStore.shared
    @State private var workout = RunWorkoutManager.shared

    init() {
        WatchStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch workout.phase {
                case .idle, .starting:
                    RunListView()
                case .running:
                    RunLiveView()
                case .finished:
                    RunFinishedView()
                }
            }
            .tint(WatchColor.accent)
        }
    }
}

/// The few colours the watch app uses (it doesn't share the iPhone's design system).
enum WatchColor {
    static let accent = Color(red: 1, green: 0.42, blue: 0.2)
    static let onPace = Color(red: 0.2, green: 0.8, blue: 0.45)
    static let offPace = Color(red: 1, green: 0.72, blue: 0.2)
    static let heart = Color(red: 1, green: 0.27, blue: 0.35)

    static func pace(_ status: PaceRange.Position?) -> Color {
        switch status {
        case .onTarget?: return onPace
        case .tooFast?, .tooSlow?: return offPace
        case nil: return .white
        }
    }
}
