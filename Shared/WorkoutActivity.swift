import Foundation
import ActivityKit
import AppIntents

/// The App Group shared by the app and its widgets (widget data lives here).
enum AppGroup {
    static let id = "group.com.georgeodwyer.kinetix"
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
}

/// The lock screen / Dynamic Island view of a workout in progress.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Mode: String, Codable, Hashable {
            case running, paused, resting, lifting
        }

        var mode: Mode
        /// For a live-counting clock while running: now minus the elapsed time.
        var timerStart: Date?
        var elapsedSeconds: Double
        // Running
        var distance: String?
        var pace: String?
        var target: String?
        /// "onTarget", "tooFast", "tooSlow" or nil when there's no target.
        var paceStatus: String?
        var step: String?
        var stepDetail: String?
        var heartRate: Int?
        // Strength
        var restEndsAt: Date?
        var setsDone: Int?
        var setsTotal: Int?
        var nextSet: String?
    }

    var title: String
    /// "run" or "strength".
    var kind: String
}

/// Pause / resume button on the lock screen. Runs inside the app.
struct ToggleWorkoutPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume workout"
    static var description = IntentDescription("Pauses or resumes the run in progress.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await MainActor.run { ActiveWorkout.shared.togglePause?() }
        #endif
        return .result()
    }
}

/// What the home and lock screen widgets show, written by the app into the App Group.
struct WidgetSnapshot: Codable, Equatable {
    struct Session: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var detail: String
        var symbol: String
        /// "run", "strength" or "other".
        var discipline: String
        var isDone: Bool
    }

    var hasPlan: Bool
    var today: [Session]
    var sessionsDone: Int
    var sessionsPlanned: Int
    var runDone: String
    var runPlanned: String
    var runFraction: Double
    var liftDone: String
    var liftPlanned: String
    var liftFraction: Double
    var loadRatio: Double?
    /// LoadStatus raw value: building, undertrained, optimal, high.
    var loadZone: String
    var loadTitle: String
    var updatedAt: Date

    static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        AppGroup.defaults?.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }

    static let placeholder = WidgetSnapshot(
        hasPlan: true,
        today: [Session(id: UUID(), title: "Tempo run", detail: "8.0 km · 45 min", symbol: "figure.run", discipline: "run", isDone: false)],
        sessionsDone: 3, sessionsPlanned: 5,
        runDone: "21 km", runPlanned: "32 km", runFraction: 0.66,
        liftDone: "6,200 kg", liftPlanned: "9,000 kg", liftFraction: 0.69,
        loadRatio: 1.08, loadZone: "optimal", loadTitle: "Optimal",
        updatedAt: .now
    )
}
