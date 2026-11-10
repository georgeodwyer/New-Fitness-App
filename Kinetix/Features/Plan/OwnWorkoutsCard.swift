import SwiftUI
import SwiftData
import TrainingEngine

/// Own gym or own runs: link saved workouts to the plan's Gym 1, Gym 2… days or run roles.
/// Linking applies to every week from today (done sessions stay as they are).
struct OwnWorkoutsCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<GymTemplateModel> { $0.deletedAt == nil }, sort: \GymTemplateModel.createdAt, order: .reverse)
    private var gymTemplates: [GymTemplateModel]
    @Query(filter: #Predicate<RunTemplateModel> { $0.deletedAt == nil }, sort: \RunTemplateModel.createdAt, order: .reverse)
    private var runTemplates: [RunTemplateModel]
    @Query(filter: #Predicate<FunctionalTemplateModel> { $0.deletedAt == nil }, sort: \FunctionalTemplateModel.createdAt, order: .reverse)
    private var functionalTemplates: [FunctionalTemplateModel]
    @State private var message: String?

    private var profile: AthleteProfile? { profiles.first?.profile }

    var body: some View {
        if let profile, profile.style == .ownGym || profile.style == .ownRuns {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                KXOverline(profile.style == .ownGym ? "Your gym workouts" : "Your run workouts")
                Text(profile.style == .ownGym
                     ? "Link a saved gym or functional workout to each gym day. Kinetix places them so leg days stay away from your hard runs."
                     : "Link a saved run workout to each kind of run. Anything not linked stays as Kinetix's session.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if profile.style == .ownGym {
                    ForEach(1...max(1, gymSlots(profile)), id: \.self) { slot in gymRow(slot, profile: profile) }
                } else {
                    ForEach(RunRole.allCases, id: \.self) { role in runRow(role, profile: profile) }
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(KXFont.caption).foregroundStyle(KXColor.ink).symbolRenderingMode(.multicolor)
                }
            }
            .kxCard()
            .accessibilityIdentifier("plan.ownWorkouts")
        }
    }

    private func gymSlots(_ profile: AthleteProfile) -> Int {
        max(profile.liftSessionsPerWeek ?? 2, profile.ownGymWorkouts?.keys.max() ?? 0)
    }

    private func gymRow(_ slot: Int, profile: AthleteProfile) -> some View {
        let linked = profile.ownGymWorkouts?[slot]
        return HStack {
            Text("Gym \(slot)").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
            Spacer()
            Menu {
                ForEach(gymTemplates) { template in
                    Button(template.name) {
                        link(gym: slot, to: OwnGymWorkout(name: template.name, exercises: template.items))
                    }
                }
                if !functionalTemplates.isEmpty {
                    Section("Functional") {
                        ForEach(functionalTemplates) { template in
                            Button(template.name) {
                                link(gym: slot, to: OwnGymWorkout(name: template.name, exercises: [], functional: template.workout))
                            }
                        }
                    }
                }
                if gymTemplates.isEmpty && functionalTemplates.isEmpty {
                    Text("No saved gym workouts yet: build one in Workout")
                }
                if linked != nil {
                    Button("Unlink", role: .destructive) { link(gym: slot, to: nil) }
                }
            } label: {
                Text(linked?.name ?? "Choose a workout")
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(linked == nil ? KXColor.accent : KXColor.ink)
            }
            .accessibilityIdentifier("plan.ownGym.\(slot)")
        }
    }

    private func runRow(_ role: RunRole, profile: AthleteProfile) -> some View {
        let linked = profile.ownRunWorkouts?[role]
        return HStack {
            Text(role.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
            Spacer()
            Menu {
                ForEach(runTemplates) { template in
                    Button(template.name) { link(run: role, to: template.workout) }
                }
                if runTemplates.isEmpty {
                    Text("No saved run workouts yet: build one in Workout")
                }
                if linked != nil {
                    Button("Use Kinetix's session", role: .destructive) { link(run: role, to: nil) }
                }
            } label: {
                Text(linked?.name ?? "Kinetix's session")
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(linked == nil ? KXColor.inkSecondary : KXColor.ink)
            }
            .accessibilityIdentifier("plan.ownRun.\(role.rawValue)")
        }
    }

    private func link(gym slot: Int, to workout: OwnGymWorkout?) {
        guard let model = profiles.first else { return }
        var updated = model.profile
        var links = updated.ownGymWorkouts ?? [:]
        links[slot] = workout
        updated.ownGymWorkouts = links.isEmpty ? nil : links
        apply(updated, to: model, message: workout.map { "Gym \(slot) is now \($0.name), from today" } ?? "Gym \(slot) unlinked")
    }

    private func link(run role: RunRole, to workout: CustomRunWorkout?) {
        guard let model = profiles.first else { return }
        var updated = model.profile
        var links = updated.ownRunWorkouts ?? [:]
        links[role] = workout
        updated.ownRunWorkouts = links.isEmpty ? nil : links
        apply(updated, to: model, message: workout.map { "\(role.title) runs are now \($0.name), from today" }
              ?? "\(role.title) runs back to Kinetix's sessions")
    }

    /// Saves the links and rebuilds the plan from today (done sessions stay).
    private func apply(_ profile: AthleteProfile, to model: UserProfileModel, message: String) {
        model.profile = profile
        try? context.save()
        PlanService.rebuildRemainder(for: profile, in: context, keepOutline: true)
        SyncService.shared.requestSync()
        withAnimation { self.message = message }
    }
}
