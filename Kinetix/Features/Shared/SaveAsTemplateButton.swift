import SwiftUI
import SwiftData
import TrainingEngine

/// Saves a finished session to reuse from the Record tab: a gym session's exercises and sets
/// (weights fill in from last time), or a run's steps and pace targets.
enum TemplateService {
    @discardableResult
    static func saveGym(_ log: StrengthLogModel, in context: ModelContext, now: Date = .now) -> String? {
        let items = GymService.items(from: log)
        guard !items.isEmpty else { return nil }
        let name = log.title.isEmpty ? "Gym session" : log.title
        let template = GymTemplateModel(name: name, items: items)
        template.lastUsedAt = now
        context.insert(template)
        try? context.save()
        SyncService.shared.requestSync()
        return name
    }

    /// The run's steps: from its planned session if there was one, else what was recorded.
    static func structure(of log: RunLogModel, in context: ModelContext) -> RunStructure? {
        if let plannedId = log.plannedSessionId,
           let planned = try? context.fetch(FetchDescriptor<PlannedSessionModel>(predicate: #Predicate { $0.id == plannedId })).first,
           let structure = planned.runStructure, !structure.segments.isEmpty {
            return structure
        }
        let segments = log.segmentResults.map(\.segment)
        return segments.isEmpty ? nil : RunStructure(segments: segments)
    }

    static func canSaveRun(_ log: RunLogModel, in context: ModelContext) -> Bool {
        structure(of: log, in: context) != nil
    }

    @discardableResult
    static func saveRun(_ log: RunLogModel, in context: ModelContext, now: Date = .now) -> String? {
        guard let structure = structure(of: log, in: context) else { return nil }
        let name = log.title.isEmpty ? "Run" : log.title
        let workout = CustomRunWorkout(name: name, type: RecordRunType(session: log.runType), structure: structure)
        let template = RunTemplateModel(workout: workout)
        template.lastUsedAt = now
        context.insert(template)
        try? context.save()
        SyncService.shared.requestSync()
        return name
    }
}

/// "Save as template" for a finished run or gym session, with a confirmation.
struct SaveAsTemplateButton: View {
    enum Source {
        case run(RunLogModel)
        case gym(StrengthLogModel)
    }

    let source: Source
    @Environment(\.modelContext) private var context
    @State private var savedName: String?

    private var available: Bool {
        switch source {
        case .run(let log): return TemplateService.canSaveRun(log, in: context)
        case .gym(let log): return !GymService.items(from: log).isEmpty
        }
    }

    var body: some View {
        if let savedName {
            Label("Saved \"\(savedName)\": start it from the Record tab", systemImage: "checkmark.circle.fill")
                .font(KXFont.callout)
                .foregroundStyle(KXColor.success)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if available {
            Button {
                switch source {
                case .run(let log): savedName = TemplateService.saveRun(log, in: context)
                case .gym(let log): savedName = TemplateService.saveGym(log, in: context)
                }
            } label: {
                Label("Save as template", systemImage: "bookmark")
            }
            .buttonStyle(.kx(.outlined, fullWidth: true))
            .accessibilityIdentifier("session.saveTemplate")
        }
    }
}
