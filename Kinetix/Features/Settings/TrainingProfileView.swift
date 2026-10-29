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
        .age, .runningExperience, .raceTime, .currentRunning, .goal, .eventDate, .gymWeek, .liftingExperience, .liftEstimates,
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

    /// e.g. "3 × Push / Pull / Legs".
    private var gymWeekText: String {
        guard model.gymWeekChosen else { return "Suggested by Kinetix" }
        guard model.liftSessionsPerWeek > 0 else { return "None" }
        let name = model.splitCode.flatMap { PlanService.templates.programmes.strength?.split($0)?.name }
        return "\(model.liftSessionsPerWeek) a week" + (name.map { " · \($0)" } ?? "")
    }

    private var changes: [String] { model.profile.planAffectingChanges(comparedTo: original) }

    /// The chosen start day, or today once the plan is under way.
    private var startBinding: Binding<Date> {
        Binding(get: {
            let today = Calendar.kinetix.startOfDay(for: .now)
            return max(model.planStartDate.map { Calendar.kinetix.startOfDay(for: $0) } ?? today, today)
        }, set: { day in
            let chosen = Calendar.kinetix.startOfDay(for: day)
            // Today means "as soon as possible", same as not choosing.
            model.planStartDate = chosen > Calendar.kinetix.startOfDay(for: .now) ? chosen : nil
            let planChanges = changes
            save()
            guard !planChanges.isEmpty else { return }
            pendingChanges = planChanges
            showRegenerate = true
        })
    }

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
                if model.goal == .hyrox {
                    row("Hyrox division", value: model.hyroxDivision?.displayName ?? "Not set", step: .goal)
                }
                row("Event date", value: model.hasEvent ? model.eventDate.formatted(.dateTime.day().month().year()) : "None", step: .eventDate)
                if model.asksGoalTime {
                    row("Target time", value: model.hasGoalTime ? Duration.seconds(model.goalTimeSeconds).formatted(.time(pattern: .hourMinuteSecond)) : "None", step: .eventDate)
                }
            }
            Section("Schedule") {
                row("Training days", value: Weekday.allCases.filter { model.trainingDays.contains($0) }.map(\.shortName).joined(separator: " "),
                    step: .trainingDays)
                row("Double sessions", value: model.doubleSessionDays == 0 ? "None" : "\(model.doubleSessionDays) day\(model.doubleSessionDays == 1 ? "" : "s")",
                    step: .doubleSessions)
                row("Gym week", value: gymWeekText, step: .gymWeek)
            }
            Section {
                row("Age", value: model.knowsAge ? "\(model.age)" : "Not given", step: .age)
                NavigationLink {
                    HeartRateZonesView(profileModel: profileModel)
                } label: {
                    LabeledContent("Heart rate zones", value: profileModel.profile.heartRateZones?.isCustom == true ? "Your own" : "Automatic")
                }
                .accessibilityIdentifier("profile.heartRateZones")
            } header: {
                Text("Heart rate")
            } footer: {
                Text("Your age gives a first estimate of your max heart rate; your runs update it.")
            }
            Section("Running") {
                row("Experience", value: model.runningExperience?.displayName ?? "–", step: .runningExperience)
                row("Recent race time", value: raceText, step: .raceTime)
                row("Running right now", value: currentRunningText, step: .currentRunning)
            }
            Section {
                DatePicker("Start on", selection: startBinding,
                           in: Calendar.kinetix.startOfDay(for: .now)...Date.now.addingTimeInterval(180 * 86_400),
                           displayedComponents: .date)
                    .accessibilityIdentifier("profile.startDate")
            } header: {
                Text("Plan")
            } footer: {
                Text("Pick a later day to start your plan then. Changing it offers to rebuild your plan from that day.")
            }
            Section("Lifting") {
                row("Experience", value: model.liftingExperience?.displayName ?? "–", step: .liftingExperience)
                row("Lift numbers", value: "\(model.liftEntries.filter(\.isKnown).count) entered", step: .liftEstimates)
                row("Equipment", value: model.equipment?.displayName ?? "–", step: .equipment)
            }
        }
        .fullScreenCover(item: $editing) { session in
            let editedLifts = session.steps.contains(.liftEstimates)
            ProfileQuestionsView(model: model, steps: session.steps, onCancel: {
                // Throw away unsaved edits.
                model.load(original)
                editing = nil
            }, onSave: {
                editing = nil
                let planChanges = changes
                save()
                // Lift numbers set the working weights again (even if they're the same as before,
                // so re-entering them fixes a plan that started from defaults).
                if editedLifts {
                    PlanService.applyLiftEstimates(profileModel.profile.liftEstimates, profile: profileModel.profile, in: context)
                }
                guard !planChanges.isEmpty else { return }
                pendingChanges = planChanges
                // Ask about the plan once the editor has closed (iOS ignores a dialog shown while it's closing).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showRegenerate = true }
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
            Button("Start from Monday (recommended)") {
                PlanService.rebuildRemainder(for: profileModel.profile, in: context, startingNextWeek: true)
                dismiss()
            }
            Button("Start today") {
                PlanService.rebuildRemainder(for: profileModel.profile, in: context)
                dismiss()
            }
            Button("Start over from week 1") {
                PlanService.createPlan(for: profileModel.profile, in: context)
                dismiss()
            }
            Button("Keep my current plan") { dismiss() }
        } message: {
            Text("You changed your \(pendingChanges.joined(separator: ", ")). From Monday keeps this week's sessions as they are and starts the new plan next week. Start today changes today's and later sessions now. Completed sessions and progress are always kept.")
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

    /// Saves every answer (age and other answers that don't change the plan too).
    private func save() {
        var updated = model.profile
        updated.units = original.units // units are changed on the Settings screen
        updated.heartRateZones = original.heartRateZones // edited on the Heart rate zones screen
        updated.exerciseSwaps = original.exerciseSwaps // set from the gym screen
        guard updated != original else { return }
        profileModel.profile = updated
        try? context.save()
        SyncService.shared.requestSync()
    }
}
