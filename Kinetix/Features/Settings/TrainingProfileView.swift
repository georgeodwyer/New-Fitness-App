import SwiftUI
import SwiftData
import TrainingEngine

/// A summary of the onboarding answers. Tapping one opens that question full-screen on the
/// onboarding screen; "Go through all questions" runs the whole set. Saving changes that
/// affect the plan offers to rebuild it.
struct TrainingProfileView: View {
    let profileModel: UserProfileModel

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var model = OnboardingModel()
    @State private var loaded = false
    @State private var pendingChanges: [String] = []
    @State private var showRegenerate = false
    @State private var editing: Editing?

    /// Questions being edited.
    private struct Editing: Identifiable {
        let id = UUID()
        let steps: [OnboardingModel.Step]
    }

    private static let allQuestions: [OnboardingModel.Step] = [
        .runningExperience, .raceTime, .currentRunning, .goal, .eventDate, .liftingExperience, .liftEstimates,
        .trainingDays, .doubleSessions, .equipment
    ]

    private var original: AthleteProfile { profileModel.profile }

    /// e.g. "25 km a week · longest 12 km".
    private var currentRunningText: String {
        guard model.knowsCurrentRunning else { return "Not given" }
        guard model.weeklyRunMeters >= 1 else { return "Not running yet" }
        let unit = Units.distanceUnitLabel(model.units)
        let weekly = Int(Units.distance(meters: model.weeklyRunMeters, in: model.units).rounded())
        let longest = Int(Units.distance(meters: model.longestRunMeters, in: model.units).rounded())
        let race = model.racedRecently ? (model.easyFirstWeek ? " · easy first week" : " · raced recently") : ""
        return "\(weekly) \(unit) a week · longest \(longest) \(unit)\(race)"
    }

    private var changes: [String] { model.profile.planAffectingChanges(comparedTo: original) }

    var body: some View {
        List {
            Section {
                Button {
                    editing = Editing(steps: Self.allQuestions)
                } label: {
                    Label("Go through all questions", systemImage: "list.bullet.rectangle.portrait")
                        .font(KXFont.bodyEmphasis)
                }
                .accessibilityIdentifier("profile.allQuestions")
            } footer: {
                Text("Or tap an answer below to change just that one.")
            }
            Section("Goal") {
                row("Primary goal", value: model.goal?.displayName ?? "–", step: .goal)
                row("Event date", value: model.hasEvent ? model.eventDate.formatted(.dateTime.day().month().year()) : "None", step: .eventDate)
            }
            Section("Schedule") {
                row("Training days", value: Weekday.allCases.filter { model.trainingDays.contains($0) }.map(\.shortName).joined(separator: " "),
                    step: .trainingDays)
                row("Double sessions", value: model.doubleSessionDays == 0 ? "None" : "\(model.doubleSessionDays) day\(model.doubleSessionDays == 1 ? "" : "s")",
                    step: .doubleSessions)
            }
            Section("Running") {
                row("Experience", value: model.runningExperience?.displayName ?? "–", step: .runningExperience)
                row("Recent race time", value: raceText, step: .raceTime)
                row("Running right now", value: currentRunningText, step: .currentRunning)
            }
            Section("Lifting") {
                row("Experience", value: model.liftingExperience?.displayName ?? "–", step: .liftingExperience)
                row("Lift numbers", value: "\(model.liftEntries.filter(\.isKnown).count) entered", step: .liftEstimates)
                row("Equipment", value: model.equipment?.displayName ?? "–", step: .equipment)
            }
        }
        .fullScreenCover(item: $editing) { session in
            ProfileQuestionsView(model: model, steps: session.steps, onCancel: {
                // Throw away unsaved edits.
                model.load(original)
                editing = nil
            }, onSave: {
                editing = nil
                guard !changes.isEmpty else { return }
                // Ask about the plan once the editor has closed (iOS ignores a dialog shown while it's closing).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { save() }
            })
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

    private func row(_ title: String, value: String, step: OnboardingModel.Step) -> some View {
        Button {
            editing = Editing(steps: [step])
        } label: {
            HStack {
                LabeledContent(title, value: value)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(KXColor.inkTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(KXColor.ink)
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
