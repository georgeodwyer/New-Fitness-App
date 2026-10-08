import SwiftUI
import TrainingEngine

/// App-wide navigation state: which tab is showing and which session is running.
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case today, plan, progress, settings
    }

    var selectedTab: Tab = .today
    /// The session currently open in the full-screen trainer, if any.
    var activeSession: ActiveSession?
}

struct ActiveSession: Identifiable, Equatable {
    let id: UUID
    let kind: SessionKind
    let title: String
}
