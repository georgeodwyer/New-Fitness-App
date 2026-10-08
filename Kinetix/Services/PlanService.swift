import Foundation
import SwiftData
import TrainingEngine

/// Bridges the training engine and the database: creates plans from a profile and
/// keeps detailed sessions generated about two weeks ahead.
@MainActor
enum PlanService {
    /// How far ahead detailed sessions are kept.
    static let horizonDays = 14

    static let templates: TemplateLibrary = {
        do {
            return try TemplateLibrary.bundled()
        } catch {
            // The templates ship inside the app; failing to load them is a build error.
            fatalError("Training templates failed to load: \(error)")
        }
    }()

    static var generator: PlanGenerator { PlanGenerator(templates: templates) }

    /// A plan preview that isn't saved (used at the end of onboarding).
    struct Preview {
        var outline: PlanOutline
        var firstWeek: GeneratedWeek?
        var zones: PaceZones
    }

    static func preview(for profile: AthleteProfile, now: Date = .now) -> Preview {
        let generator = generator
        let outline = generator.makeOutline(for: profile, startingOn: generator.planStart(from: now))
        let firstWeek = generator.generateWeek(0, outline: outline, profile: profile, notBefore: now)
        return Preview(outline: outline, firstWeek: firstWeek, zones: PaceZones(profile: profile))
    }

    /// Replaces the active plan with a freshly generated one. Completed sessions and
    /// logs are kept; future planned sessions of the old plan are removed.
    @discardableResult
    static func createPlan(for profile: AthleteProfile, in context: ModelContext, now: Date = .now) -> TrainingPlanModel {
        let today = Calendar.kinetix.startOfDay(for: now)
        let existing = (try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? []
        for plan in existing where plan.isActive {
            plan.isActive = false
            plan.touch(now: now)
            for session in plan.sessions where session.status == .planned && session.date >= today {
                session.softDelete(now: now)
            }
        }

        let generator = generator
        let outline = generator.makeOutline(for: profile, startingOn: generator.planStart(from: now))
        let plan = TrainingPlanModel(goal: profile.goal, startDate: outline.startDate, endDate: outline.eventDate)
        plan.outline = outline
        context.insert(plan)
        context.insert(PlanChangeModel(summary: "Created a new \(outline.weeks.count)-week plan for \(profile.goal.displayName.lowercased()).", now: now))

        ensureHorizon(for: plan, profile: profile, in: context, now: now)
        try? context.save()
        return plan
    }

    /// Generates further weeks so sessions always exist about two weeks ahead.
    static func ensureHorizon(for plan: TrainingPlanModel, profile: AthleteProfile, in context: ModelContext, now: Date = .now) {
        guard let outline = plan.outline else { return }
        let calendar = Calendar.kinetix
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: calendar.startOfDay(for: now)) ?? now
        let generator = generator
        let weights = workingWeights(in: context)

        while plan.generatedWeekCount < outline.weeks.count,
              outline.weeks[plan.generatedWeekCount].startDate <= horizon {
            let index = plan.generatedWeekCount
            if let week = generator.generateWeek(index, outline: outline, profile: profile, workingWeights: weights, notBefore: now) {
                for generated in week.sessions {
                    let session = PlannedSessionModel(generated: generated, weekIndex: index)
                    context.insert(session)
                    session.plan = plan
                    registerExercises(generated.strength, in: context, existing: weights)
                }
                for note in week.notes {
                    context.insert(PlanChangeModel(summary: note, now: now))
                }
            }
            plan.generatedWeekCount += 1
            plan.touch(now: now)
        }
    }

    /// Tops up the active plan's horizon (call on launch / foreground).
    static func refresh(in context: ModelContext, now: Date = .now) {
        guard let profileModel = try? context.fetch(FetchDescriptor<UserProfileModel>()).first(where: { !$0.isSoftDeleted }),
              let plan = try? context.fetch(FetchDescriptor<TrainingPlanModel>()).first(where: { $0.isActive && !$0.isSoftDeleted })
        else { return }
        let before = plan.generatedWeekCount
        ensureHorizon(for: plan, profile: profileModel.profile, in: context, now: now)
        if plan.generatedWeekCount != before { try? context.save() }
    }

    /// Current working weights by progression key.
    static func workingWeights(in context: ModelContext) -> [String: Double] {
        let states = (try? context.fetch(FetchDescriptor<ExerciseStateModel>())) ?? []
        return Dictionary(states.filter { !$0.isSoftDeleted }.map { ($0.progressionKey, $0.workingWeightKg) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// Records starting weights for exercises seen for the first time.
    private static func registerExercises(_ prescription: StrengthPrescription?, in context: ModelContext, existing: [String: Double]) {
        guard let prescription else { return }
        for exercise in prescription.exercises {
            guard let weight = exercise.weightKg, existing[exercise.progressionKey] == nil else { continue }
            let key = exercise.progressionKey
            let descriptor = FetchDescriptor<ExerciseStateModel>(predicate: #Predicate { $0.progressionKey == key })
            if let count = try? context.fetchCount(descriptor), count > 0 { continue }
            context.insert(ExerciseStateModel(
                progressionKey: key,
                exerciseId: exercise.exerciseId,
                workingWeightKg: weight,
                repRangeLower: exercise.repRange.lower,
                repRangeUpper: exercise.repRange.upper
            ))
        }
    }
}

extension TrainingGoal {
    var displayName: String {
        switch self {
        case .first5k: return "First 5K"
        case .faster10k: return "Faster 10K"
        case .halfMarathon: return "Half marathon"
        case .marathon: return "Marathon"
        case .buildStrength: return "Build strength"
        case .buildMuscle: return "Build muscle"
        case .balancedHybrid: return "Balanced hybrid fitness"
        }
    }
}
