import SwiftUI
import SwiftData
import TrainingEngine

/// Full-screen container that opens the right trainer for a session.
struct SessionContainerView: View {
    let session: ActiveSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfileModel]
    @State private var strengthModel: StrengthWorkoutModel?

    var body: some View {
        Group {
            switch session.kind {
            case .strength:
                if let strengthModel {
                    StrengthWorkoutView(model: strengthModel, units: profiles.first?.units ?? .metric) { dismiss() }
                } else {
                    ProgressView().onAppear(perform: startStrength)
                }
            default:
                SessionPlaceholderView(session: session)
            }
        }
    }

    private func startStrength() {
        let id = session.id
        let planned = try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
        guard let planned else { dismiss(); return }
        let log = StrengthService.startOrResume(planned, in: context)
        strengthModel = StrengthWorkoutModel(log: log, planned: planned, context: context)
    }
}
