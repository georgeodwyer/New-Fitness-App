import SwiftUI
import SwiftData
import TrainingEngine

/// Ill, injured or away: pause the plan, and pick it back up when you're ready.
struct PausePlanSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var reason: PlanService.PauseReason = .ill
    @State private var knowsReturn = false
    @State private var until = Calendar.kinetix.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your sessions are cleared until you're back, and nothing counts as missed. When you resume, the plan picks up from the week you paused in.")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                Section("Why are you pausing?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(PlanService.PauseReason.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if reason.easesBackIn {
                        Text("Your first week back will be an easier one. If you're injured, check with a professional before starting again.")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                Section {
                    Toggle("I know when I'll be back", isOn: $knowsReturn)
                    if knowsReturn {
                        DatePicker("Back on", selection: $until, in: Date.now..., displayedComponents: .date)
                    }
                } footer: {
                    Text(knowsReturn ? "We'll remind you that morning. You can resume earlier any time." : "Resume whenever you're ready from Today or the Plan tab.")
                }
            }
            .navigationTitle("Pause plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pause") {
                        PlanService.pause(reason: reason, until: knowsReturn ? until : nil, in: context)
                        Task { await NotificationService.scheduleMornings(in: context) }
                        dismiss()
                    }
                    .accessibilityIdentifier("pause.confirm")
                }
            }
        }
        .tint(KXColor.accent)
    }
}

/// Shown on Today and the Plan tab while the plan is paused.
struct PausedPlanCard: View {
    let plan: TrainingPlanModel
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]

    private var reason: PlanService.PauseReason { plan.pauseReasonRaw.flatMap(PlanService.PauseReason.init(rawValue:)) ?? .other }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXOverline("Plan paused", color: KXColor.warning)
            Text(detail).font(KXFont.callout).foregroundStyle(KXColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Recovery and your check-in carry on as normal. Light movement only when you feel up to it.")
                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            Button {
                if let profile = profiles.first?.profile {
                    PlanService.resume(profile: profile, in: context)
                    Task { await NotificationService.scheduleMornings(in: context) }
                }
            } label: {
                Label("I'm back: resume my plan", systemImage: "play.fill")
            }
            .buttonStyle(.kx(.primary, fullWidth: true))
            .accessibilityIdentifier("plan.resume")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxCard()
    }

    private var detail: String {
        let since = plan.pausedAt.map { $0.formatted(.dateTime.weekday(.wide).day().month()) } ?? "recently"
        var text = "\(reason.title) since \(since)."
        if let until = plan.pauseUntil { text += " Back around \(until.formatted(.dateTime.weekday(.wide).day().month()))." }
        return text
    }
}
