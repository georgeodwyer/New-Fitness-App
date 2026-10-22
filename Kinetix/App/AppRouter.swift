import SwiftUI
import TrainingEngine

/// App-wide navigation state: which tab is showing and which session is running.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case today, plan, record, progress, settings
    }

    var selectedTab: Tab = .today
    /// The session currently running (open full screen, or minimised to the bar above the tabs).
    private(set) var activeSession: ActiveSession?
    /// The running workout's state lives here, so it keeps going while minimised.
    var runModel: RunWorkoutModel?
    var strengthModel: StrengthWorkoutModel?
    /// The trainer is closed down to the bar above the tabs.
    private(set) var isMinimised = false

    /// Opens a session full screen. While another one is running, that one is reopened instead.
    func start(_ session: ActiveSession) {
        if activeSession != nil {
            isMinimised = false
            return
        }
        runModel = nil
        strengthModel = nil
        isMinimised = false
        activeSession = session
    }

    func minimise() {
        guard activeSession != nil else { return }
        isMinimised = true
    }

    func restore() { isMinimised = false }

    /// The session has finished, been saved or been left.
    func endSession() {
        strengthModel?.endLockScreen()
        WorkoutActivityController.shared.end()
        activeSession = nil
        runModel = nil
        strengthModel = nil
        isMinimised = false
    }

    /// What the full-screen cover shows: the session, unless it's minimised.
    var presentedSession: ActiveSession? {
        get { isMinimised ? nil : activeSession }
        set { if newValue == nil && !isMinimised { endSession() } }
    }
}

struct ActiveSession: Identifiable, Equatable {
    let id: UUID
    let kind: SessionKind
    let title: String
    /// A run built on the Record tab (instead of a planned session).
    var custom: CustomRunWorkout? = nil
    /// The planned session a recorded run counts as, if the runner said so.
    var linkedPlannedId: UUID? = nil
    /// A gym workout started (or resumed) from the Record tab.
    var strengthLogId: UUID? = nil
    /// A planned route to follow on a run started from the Record tab.
    var route: PlannedRoute? = nil
}
