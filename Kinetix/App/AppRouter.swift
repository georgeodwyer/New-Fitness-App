import SwiftUI
import TrainingEngine

/// App-wide navigation state: which tab is showing and which session is running.
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case today, plan, record, progress, settings
    }

    var selectedTab: Tab = .today
    /// The session currently open in the full-screen trainer, if any.
    var activeSession: ActiveSession?
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
