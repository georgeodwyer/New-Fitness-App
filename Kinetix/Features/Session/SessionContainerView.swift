import SwiftUI
import SwiftData
import TrainingEngine

/// Full-screen container that opens the right trainer for a session.
struct SessionContainerView: View {
    let session: ActiveSession
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<CoachingSettingsModel> { $0.deletedAt == nil }) private var coachingSettings: [CoachingSettingsModel]
    @AppStorage(DeveloperSettings.simulateGPSKey) private var simulateGPS = false
    @AppStorage(DeveloperSettings.simulationSpeedKey) private var simulationSpeed = 10.0
    private var strengthModel: StrengthWorkoutModel? { router.strengthModel }
    private var runModel: RunWorkoutModel? { router.runModel }

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }

    var body: some View {
        Group {
            switch session.kind {
            case .strength:
                if let strengthModel {
                    StrengthWorkoutView(model: strengthModel, units: units) { close() } onMinimise: { router.minimise() }
                } else {
                    ProgressView().onAppear(perform: startStrength)
                }
            case .run:
                if let runModel {
                    RunWorkoutView(model: runModel) { close() } onMinimise: { router.minimise() }
                } else {
                    ProgressView().onAppear(perform: startRun)
                }
            default:
                SessionPlaceholderView(session: session)
            }
        }
        // Whatever way the session ends, the lock-screen view goes with it, and the widgets
        // pick up the finished session. (Minimising keeps both going.)
        .onDisappear {
            guard router.activeSession == nil else { return }
            WidgetSnapshotService.update(in: context)
        }
    }

    private func close() { router.endSession() }

    private func plannedSession() -> PlannedSessionModel? {
        guard let id = session.custom == nil ? session.id : session.linkedPlannedId else { return nil }
        return try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
    }

    private func startStrength() {
        if let logId = session.strengthLogId {
            guard let log = try? context.fetch(FetchDescriptor<StrengthLogModel>(predicate: #Predicate { $0.id == logId })).first else {
                close(); return
            }
            let plannedId = log.plannedSessionId
            let planned = plannedId.flatMap { id in
                try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
            }
            router.strengthModel = StrengthWorkoutModel(log: log, planned: planned, context: context, units: units)
            return
        }
        guard let planned = plannedSession() else { close(); return }
        let log = StrengthService.startOrResume(planned, in: context)
        router.strengthModel = StrengthWorkoutModel(log: log, planned: planned, context: context, units: units)
    }

    private func startRun() {
        let speed = DeveloperSettings.launchSimulationSpeed ?? (simulateGPS ? simulationSpeed : nil)
        router.runModel = RunWorkoutModel(
            planned: plannedSession(),
            custom: session.custom,
            route: session.route,
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
