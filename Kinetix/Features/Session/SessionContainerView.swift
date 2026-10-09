import SwiftUI
import SwiftData
import TrainingEngine

/// Full-screen container that opens the right trainer for a session.
struct SessionContainerView: View {
    let session: ActiveSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfileModel]
    @Query private var coachingSettings: [CoachingSettingsModel]
    @AppStorage(DeveloperSettings.simulateGPSKey) private var simulateGPS = false
    @AppStorage(DeveloperSettings.simulationSpeedKey) private var simulationSpeed = 10.0
    @State private var strengthModel: StrengthWorkoutModel?
    @State private var runModel: RunWorkoutModel?

    private var units: UnitSystem { profiles.first?.units ?? .metric }

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
    }

    private func plannedSession() -> PlannedSessionModel? {
        let id = session.id
        return try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == id })).first
    }

    private func startStrength() {
        guard let planned = plannedSession() else { dismiss(); return }
        let log = StrengthService.startOrResume(planned, in: context)
        strengthModel = StrengthWorkoutModel(log: log, planned: planned, context: context)
    }

    private func startRun() {
        let speed = DeveloperSettings.launchSimulationSpeed ?? (simulateGPS ? simulationSpeed : nil)
        runModel = RunWorkoutModel(
            planned: plannedSession(),
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
