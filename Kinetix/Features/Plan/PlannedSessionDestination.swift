import SwiftUI
import SwiftData
import TrainingEngine

/// Opening a planned session: what you did once it's done (the run or gym session that
/// completed it), otherwise the plan's details.
struct PlannedSessionDestination: View {
    let session: PlannedSessionModel
    @Query private var runs: [RunLogModel]
    @Query private var lifts: [StrengthLogModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]

    init(session: PlannedSessionModel) {
        self.session = session
        let id: UUID? = session.id
        _runs = Query(filter: #Predicate<RunLogModel> { $0.plannedSessionId == id && $0.isFinished })
        _lifts = Query(filter: #Predicate<StrengthLogModel> { $0.plannedSessionId == id && $0.isFinished })
    }

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }

    var body: some View {
        if session.status == .completed, let run = runs.first(where: { !$0.isSoftDeleted }) {
            RunDetailView(log: run, units: units)
        } else if session.status == .completed, let lift = lifts.first(where: { !$0.isSoftDeleted }) {
            StrengthSessionDetailView(log: lift, units: units)
        } else {
            SessionDetailView(session: session)
        }
    }
}
