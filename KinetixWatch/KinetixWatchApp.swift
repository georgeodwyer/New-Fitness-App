import SwiftUI
import HealthKit
import WatchKit
import TrainingEngine

@main
struct KinetixWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
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
                    if workout.isGym { GymLiveView() } else { RunLiveView() }
                case .finished:
                    RunFinishedView()
                }
            }
            .tint(WatchColor.accent)
        }
    }
}

/// Opens the app when a run starts on the iPhone, so the watch can show it.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await RunWorkoutManager.shared.startMirroring(configuration: workoutConfiguration)
        }
    }
}
