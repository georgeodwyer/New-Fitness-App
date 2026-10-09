import SwiftUI
import SwiftData
import TrainingEngine

/// Edit onboarding answers. Each item opens the same question screen as onboarding.
/// Saving changes that affect the plan offers to regenerate it.
struct TrainingProfileView: View {
    let profileModel: UserProfileModel

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = OnboardingModel()
    @State private var loaded = false
    @State private var pendingChanges: [String] = []
    @State private var showRegenerate = false

    private var original: AthleteProfile { profileModel.profile }

    private var changes: [String] { model.profile.planAffectingChanges(comparedTo: original) }

    var body: some View {
        List {
            Section("Goal") {
                row("Primary goal", value: model.goal?.displayName ?? "–") { GoalStep(model: model) }
                row("Event date", value: model.hasEvent ? model.eventDate.formatted(.dateTime.day().month().year()) : "None") {
                    EventDateStep(model: model)
                }
            }
            Section("Schedule") {
                row("Training days", value: Weekday.allCases.filter { model.trainingDays.contains($0) }.map(\.shortName).joined(separator: " ")) {
                    TrainingDaysStep(model: model)
                }
                row("Double sessions", value: model.doubleSessionDays == 0 ? "None" : "\(model.doubleSessionDays) day\(model.doubleSessionDays == 1 ? "" : "s")") {
                    DoubleSessionsStep(model: model)
                }
            }
            Section("Running") {
                row("Experience", value: model.runningExperience?.displayName ?? "–") { RunningExperienceStep(model: model) }
                row("Recent race time", value: raceText) { RaceTimeStep(model: model) }
            }
            Section("Lifting") {
                row("Experience", value: model.liftingExperience?.displayName ?? "–") { LiftingExperienceStep(model: model) }
                row("Lift numbers", value: "\(model.liftEntries.filter(\.isKnown).count) entered") { LiftEstimatesStep(model: model) }
                row("Equipment", value: model.equipment?.displayName ?? "–") { EquipmentStep(model: model) }
            }
            if !changes.isEmpty {
                Section {
                    Button {
                        save()
                    } label: {
                        Label("Save changes", systemImage: "checkmark.circle.fill").font(KXFont.bodyEmphasis)
                    }
                } footer: {
                    Text("Changed: \(changes.joined(separator: ", ")).")
                }
            }
        }
        .navigationTitle("Training profile")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .onAppear {
            guard !loaded else { return }
            model.load(original)
            loaded = true
        }
        .confirmationDialog("Update your plan?", isPresented: $showRegenerate, titleVisibility: .visible) {
            Button("Rebuild my plan") {
                PlanService.createPlan(for: profileModel.profile, in: context)
                dismiss()
            }
            Button("Keep my current plan") { dismiss() }
        } message: {
            Text("You changed your \(pendingChanges.joined(separator: ", ")). Rebuild your upcoming sessions to match? Completed sessions and progress are kept.")
        }
    }

    private var raceText: String {
        guard model.knowsRaceTime else { return "Not set" }
        return "\(model.raceDistance.label) in \(Units.formatMinutesSeconds(model.raceTimeSeconds))"
    }

    private func row<Destination: View>(_ title: String, value: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) { destination() }
                    .padding(KXSpacing.screenMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            LabeledContent(title, value: value)
        }
    }

    private func save() {
        pendingChanges = changes
        var updated = model.profile
        updated.units = original.units // units are changed on the Settings screen
        profileModel.profile = updated
        try? context.save()
        showRegenerate = true
    }
}
