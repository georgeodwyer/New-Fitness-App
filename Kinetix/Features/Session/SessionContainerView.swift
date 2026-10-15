import SwiftUI
import SwiftData
import TrainingEngine

/// Full-screen container that opens the right trainer for a session.
struct SessionContainerView: View {
    let session: ActiveSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<CoachingSettingsModel> { $0.deletedAt == nil }) private var coachingSettings: [CoachingSettingsModel]
    @AppStorage(DeveloperSettings.simulateGPSKey) private var simulateGPS = false
    @AppStorage(DeveloperSettings.simulationSpeedKey) private var simulationSpeed = 10.0
    @State private var strengthModel: StrengthWorkoutModel?
    @State private var runModel: RunWorkoutModel?

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }

    var body: some View {
        Group {
            switch session.kind {
            case .strength:
                if let strengthModel {
                    StrengthWorkoutView(model: strengthModel, units: units) { dismiss() }
                } else {
                    ProgressView().onAppear(perform: startStrength)
                }
            case .run:
                if let runModel {
                    RunWorkoutView(model: runModel) { dismiss() }
                } else {
                    ProgressView().onAppear(perform: startRun)
                }
            default:
                SessionPlaceholderView(session: session)
            }
        }
        // Whatever way the workout screen closes, the lock-screen view goes with it,
        // and the widgets pick up the finished session.
        .onDisappear {
            strengthModel?.endLockScreen()
            WorkoutActivityController.shared.end()
            WidgetSnapshotService.update(in: context)
        }
    }

    private func plannedSession() -> PlannedSessionModel? {
        guard let id = session.custom == nil ? session.id : session.linkedPlannedId else { return nil }
        return try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
    }

    private func startStrength() {
        if let logId = session.strengthLogId {
            guard let log = try? context.fetch(FetchDescriptor<StrengthLogModel>(predicate: #Predicate { $0.id == logId })).first else {
                dismiss(); return
            }
            let plannedId = log.plannedSessionId
            let planned = plannedId.flatMap { id in
                try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
            }
            strengthModel = StrengthWorkoutModel(log: log, planned: planned, context: context, units: units)
            return
        }
        guard let planned = plannedSession() else { dismiss(); return }
        let log = StrengthService.startOrResume(planned, in: context)
        strengthModel = StrengthWorkoutModel(log: log, planned: planned, context: context, units: units)
    }

    private func startRun() {
        let speed = DeveloperSettings.launchSimulationSpeed ?? (simulateGPS ? simulationSpeed : nil)
        runModel = RunWorkoutModel(
            planned: plannedSession(),
            custom: session.custom,
            units: units,
            settings: coachingSettings.first,
            simulationSpeed: speed,
            context: context
        )
    }
}

/// Developer options for trying features without real-world conditions.
enum DeveloperSettings {
    static let simulateGPSKey = "developer.simulateGPS"
    static let simulationSpeedKey = "developer.simulationSpeed"

    /// `-simulate-gps <speed>` launch argument (used by the automated screenshots).
    static var launchSimulationSpeed: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-simulate-gps") else { return nil }
        let next = arguments.index(after: index)
        return next < arguments.endIndex ? Double(arguments[next]) ?? 10 : 10
    }
}
