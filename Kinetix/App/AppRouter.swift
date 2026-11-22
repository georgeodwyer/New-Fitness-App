import SwiftUI
import SwiftData
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
    var functionalModel: FunctionalWorkoutModel?
    /// The trainer is closed down to the bar above the tabs.
    private(set) var isMinimised = false

    /// A planned session waiting on "change it or keep as planned?" (recovery below par, or
    /// sore legs or upper body for a session that works them).
    struct PendingReduction: Identifiable {
        let session: PlannedSessionModel
        let offer: BalanceService.RecoveryOffer
        var id: UUID { session.id }
    }
    var pendingReduction: PendingReduction?

    /// Starts a planned session, first offering a change when recovery or soreness says so.
    func startPlanned(_ session: PlannedSessionModel, in context: ModelContext) {
        if activeSession == nil, let offer = BalanceService.recoveryOffer(for: session, in: context) {
            pendingReduction = PendingReduction(session: session, offer: offer)
            return
        }
        start(ActiveSession(id: session.id, kind: session.kind, title: session.title))
    }

    enum ReductionAnswer { case takeChange, keep, swap, move }

    /// The answer to the offer.
    func answerReduction(_ answer: ReductionAnswer, in context: ModelContext) {
        guard let pending = pendingReduction else { return }
        pendingReduction = nil
        let profile = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first { !$0.isSoftDeleted }?.profile
        switch answer {
        case .takeChange:
            if let option = pending.offer.option {
                BalanceService.takeOffered(pending.session, option: option, recovery: pending.offer.recovery, in: context)
            }
            start(ActiveSession(id: pending.session.id, kind: pending.session.kind, title: pending.session.title))
        case .keep:
            start(ActiveSession(id: pending.session.id, kind: pending.session.kind, title: pending.session.title))
        case .swap:
            // Today becomes the other gym session: start that one.
            guard let other = pending.offer.swapWith, let profile else { return }
            BalanceService.swapDays(pending.session, with: other, profile: profile, in: context)
            start(ActiveSession(id: other.id, kind: other.kind, title: other.title))
        case .move:
            guard let day = pending.offer.moveTo, let profile else { return }
            BalanceService.move(pending.session, to: day, profile: profile, in: context)
        }
    }

    /// Opens a session full screen. While another one is running, that one is reopened instead.
    func start(_ session: ActiveSession) {
        if activeSession != nil {
            isMinimised = false
            return
        }
        runModel = nil
        strengthModel = nil
        functionalModel?.stop()
        functionalModel = nil
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
        functionalModel?.stop()
        functionalModel = nil
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
    /// A functional workout (circuit / Hyrox style) started from the Workout tab.
    var functional: FunctionalWorkout? = nil
    /// The saved functional workout it came from, if any.
    var functionalTemplateId: UUID? = nil
}
