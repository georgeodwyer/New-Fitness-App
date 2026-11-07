import SwiftUI
import SwiftData
import TrainingEngine

/// Workout → Workout bank: every Kinetix gym session (full body, upper / lower, push / pull /
/// legs, runner strength, Hyrox…), with exercises for your equipment. Start one, or save it to
/// your gym workouts to change it.
struct WorkoutBankView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @State private var startRequest: GymStartRequest?
    @State private var showing: BankWorkout?
    @State private var savedMessage: String?
    @State private var expanded: Set<String> = []

    private var profile: AthleteProfile? { profiles.first?.profile }

    private var bank: [BankGroup] {
        PlanService.templates.workoutBank(equipment: profile?.equipment ?? .fullGym, goal: profile?.goal ?? .balancedHybrid)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                Text("Fancy something different? Every gym session Kinetix uses, with exercises for your equipment. Start one now or save it to your workouts.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(KXFont.caption).foregroundStyle(KXColor.ink).symbolRenderingMode(.multicolor)
                }
                ForEach(bank) { group in groupCard(group) }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Workout bank")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showing) { workout in
            BankWorkoutSheet(workout: workout, units: profiles.first?.units ?? UnitPreference.stored) {
                showing = nil
                startRequest = GymStartRequest(title: workout.name, items: workout.items)
            } onSave: {
                save(workout)
                showing = nil
            }
            .presentationDetents([.medium, .large])
        }
        .gymStartFlow($startRequest)
    }

    private func groupCard(_ group: BankGroup) -> some View {
        let isOpen = expanded.contains(group.id)
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Button {
                withAnimation { if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) } }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text(group.suits.isEmpty ? "\(group.workouts.count) sessions" : group.suits)
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bank.group.\(group.id)")
            if isOpen {
                ForEach(group.workouts) { workout in
                    Button { showing = workout } label: {
                        HStack(spacing: KXSpacing.md) {
                            Image(systemName: "dumbbell.fill")
                                .foregroundStyle(KXColor.lift)
                                .frame(width: 32, height: 32)
                                .background(KXColor.lift.opacity(0.12), in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                Text(workout.items.map(\.name).joined(separator: ", "))
                                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(KXSpacing.sm)
                        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .kxCard()
    }

    private func save(_ workout: BankWorkout) {
        context.insert(GymTemplateModel(name: workout.name, items: workout.items))
        try? context.save()
        SyncService.shared.requestSync()
        withAnimation { savedMessage = "\(workout.name) saved to your gym workouts" }
    }
}

/// One bank workout: its exercises, then Start or Save.
private struct BankWorkoutSheet: View {
    let workout: BankWorkout
    let units: UnitSystem
    let onStart: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    Text(GymTemplate.summary(workout.items)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    ForEach(workout.items) { item in
                        HStack {
                            Text(item.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                            Spacer()
                            Text(item.repsLow == item.repsHigh ? "\(item.sets) × \(item.repsLow)" : "\(item.sets) × \(item.repsLow)–\(item.repsHigh)")
                                .font(KXFont.callout.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                        }
                        .padding(.vertical, KXSpacing.xxs)
                        .accessibilityElement(children: .combine)
                    }
                    Button(action: onStart) {
                        Label("Start this workout", systemImage: "play.fill")
                    }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .accessibilityIdentifier("bank.start")
                    Button(action: onSave) {
                        Label("Save to my gym workouts", systemImage: "bookmark")
                    }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
                    Text("Weights fill in from what you lifted last time.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                }
                .padding(KXSpacing.screenMargin)
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
