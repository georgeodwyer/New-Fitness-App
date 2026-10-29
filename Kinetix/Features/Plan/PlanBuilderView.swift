import SwiftUI
import SwiftData
import TrainingEngine

/// Build my own plan: basics, a typical week (saved workouts, Kinetix runs and gym sessions),
/// then how it builds up, with a preview. Editing an existing plan changes it from next Monday.
struct PlanBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<RunTemplateModel> { $0.deletedAt == nil }, sort: \RunTemplateModel.createdAt, order: .reverse)
    private var runTemplates: [RunTemplateModel]
    @Query(filter: #Predicate<GymTemplateModel> { $0.deletedAt == nil }, sort: \GymTemplateModel.createdAt, order: .reverse)
    private var gymTemplates: [GymTemplateModel]

    @State private var plan: CustomPlan
    @State private var step = 0
    @State private var addingTo: Weekday?
    private let isEditing: Bool

    init(existing: CustomPlan? = nil) {
        isEditing = existing != nil
        let calendar = Calendar.kinetix
        let thisMonday = calendar.startOfISOWeek(for: .now)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: thisMonday) ?? thisMonday
        _plan = State(initialValue: existing ?? CustomPlan(name: "My plan", weeks: 12, startDate: nextMonday))
    }

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }
    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule().fill(index <= step ? KXColor.accent : KXColor.border).frame(height: 4)
                    }
                }
                .padding(.horizontal, KXSpacing.screenMargin)
                .padding(.vertical, KXSpacing.sm)
                ScrollView {
                    VStack(alignment: .leading, spacing: KXSpacing.lg) {
                        switch step {
                        case 0: basics
                        case 1: week
                        default: progression
                        }
                    }
                    .padding(KXSpacing.screenMargin)
                }
            }
            .background(KXColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(["Build my own plan", "Your typical week", "Progression"][step])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "Cancel" : "Back") { if step == 0 { dismiss() } else { withAnimation { step -= 1 } } }
                }
            }
            .sheet(item: $addingTo) { day in
                AddPlanSessionSheet(day: day, units: units, runTemplates: runTemplates, gymTemplates: gymTemplates) { item in
                    plan.items.append(item)
                    addingTo = nil
                }
                .presentationDetents([.medium, .large])
            }
        }
        .tint(KXColor.accent)
    }

    private var footer: some View {
        Button {
            if step < 2 { withAnimation { step += 1 } } else { save() }
        } label: {
            Text(step == 0 ? "Next: your typical week" : step == 1 ? "Next: progression" : isEditing ? "Save (starts Monday)" : "Create my plan")
        }
        .buttonStyle(.kx(.primary, fullWidth: true))
        .disabled(step == 1 && plan.items.isEmpty)
        .padding(KXSpacing.screenMargin)
        .background(KXColor.background)
        .accessibilityIdentifier("builder.next")
    }

    // MARK: 1 · Basics

    private var basics: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text("YOUR PLAN, YOUR WAY").font(KXFont.display).foregroundStyle(KXColor.ink)
                Text("Set up a typical week once. Kinetix repeats it and builds it up week by week, with easier weeks to recover.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                TextField("Plan name", text: $plan.name)
                    .font(KXFont.bodyEmphasis)
                    .padding(KXSpacing.sm)
                    .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm))
                Stepper(value: $plan.weeks, in: 4...24) {
                    LabeledContent("Length", value: "\(plan.weeks) weeks")
                }
                .disabled(plan.hasRace)
                DatePicker("Starts (Monday)", selection: startBinding, displayedComponents: .date)
            }
            .kxCard()
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                Toggle("Building to a race?", isOn: raceBinding)
                if plan.hasRace {
                    Picker("Distance", selection: Binding(get: { plan.raceMeters ?? 21097.5 }, set: { plan.raceMeters = $0 })) {
                        Text("5K").tag(5000.0)
                        Text("10K").tag(10000.0)
                        Text("Half").tag(21097.5)
                        Text("Marathon").tag(42195.0)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Race day", selection: raceDateBinding, in: plan.startDate.addingTimeInterval(21 * 86_400)...,
                               displayedComponents: .date)
                    Text("\(plan.weeks) weeks, and the last two taper automatically so you race fresh.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            }
            .kxCard()
        }
    }

    private var startBinding: Binding<Date> {
        Binding(get: { plan.startDate }, set: { date in
            plan.startDate = Calendar.kinetix.startOfISOWeek(for: date)
            fitWeeksToRace()
        })
    }

    private var raceBinding: Binding<Bool> {
        Binding(get: { plan.hasRace }, set: { on in
            if on {
                plan.raceMeters = plan.raceMeters ?? 21097.5
                plan.raceDate = plan.raceDate ?? Calendar.kinetix.date(byAdding: .day, value: 7 * plan.weeks - 1, to: plan.startDate)
                fitWeeksToRace()
            } else {
                plan.raceMeters = nil
                plan.raceDate = nil
            }
        })
    }

    private var raceDateBinding: Binding<Date> {
        Binding(get: { plan.raceDate ?? plan.startDate }, set: { plan.raceDate = $0; fitWeeksToRace() })
    }

    /// With a race, the plan runs from the start Monday to race week.
    private func fitWeeksToRace() {
        guard let race = plan.raceDate else { return }
        let calendar = Calendar.kinetix
        let days = calendar.dateComponents([.day], from: plan.startDate, to: calendar.startOfISOWeek(for: race)).day ?? 0
        plan.weeks = min(max(days / 7 + 1, 4), 30)
    }

    // MARK: 2 · Typical week

    private var week: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Text("Tap + on a day to add a session. Distances build up from week 1; press and hold a session to remove it or change its time.")
                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            ForEach(Weekday.allCases, id: \.self) { day in
                dayRow(day)
            }
        }
    }

    private func dayRow(_ day: Weekday) -> some View {
        let items = plan.items.filter { $0.weekday == day }.sorted { $0.slot == .morning && $1.slot == .evening }
        let hasLong = items.contains { if case .run(.long, _) = $0.activity { return true } else { return false } }
        return HStack(alignment: .top, spacing: KXSpacing.md) {
            Text(day.shortName.uppercased())
                .font(KXFont.overline).foregroundStyle(hasLong ? KXColor.accent : KXColor.inkSecondary)
                .frame(width: 36, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                if items.isEmpty {
                    Text("Rest").font(KXFont.callout).foregroundStyle(KXColor.inkTertiary)
                }
                ForEach(items) { item in
                    HStack(spacing: KXSpacing.sm) {
                        Circle().fill(color(item.activity)).frame(width: 8, height: 8)
                        Text(title(item.activity)).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                        Text(detail(item)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            if let index = plan.items.firstIndex(where: { $0.id == item.id }) {
                                plan.items[index].slot = item.slot == .morning ? .evening : .morning
                            }
                        } label: {
                            Label(item.slot == .morning ? "Move to evening" : "Move to morning", systemImage: "clock")
                        }
                        Button(role: .destructive) {
                            plan.items.removeAll { $0.id == item.id }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                addingTo = day
            } label: {
                Image(systemName: "plus").font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(KXColor.surfaceTint, in: Circle())
            }
            .accessibilityLabel("Add a session on \(day.fullName)")
        }
        .padding(KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            if hasLong { RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).strokeBorder(KXColor.accent.opacity(0.7), lineWidth: 1) }
        }
    }

    private func title(_ activity: CustomPlan.Activity) -> String {
        switch activity {
        case .run(let type, _): return SessionKind.run(type).displayName
        case .runWorkout(let workout): return workout.name
        case .gymSession(let key): return PlanService.templates.strength.sessions[key]?.name ?? "Gym"
        case .gymWorkout(let name, _): return name
        case .crossTraining: return SessionKind.crossTraining.displayName
        }
    }

    private func detail(_ item: CustomPlan.Item) -> String {
        let slot = item.slot == .evening ? " · evening" : ""
        switch item.activity {
        case .run(let type, let meters):
            if type == .tempo || type == .intervals { return "Kinetix session" + slot }
            return format.distance(meters, decimals: 0) + (type == .long ? " → builds" : "") + slot
        case .runWorkout: return "my run workout" + slot
        case .gymSession: return "Kinetix gym" + slot
        case .gymWorkout(_, let exercises): return "\(exercises.count) exercises" + slot
        case .crossTraining(let minutes): return "\(Int(minutes)) min" + slot
        }
    }

    private func color(_ activity: CustomPlan.Activity) -> Color {
        switch activity.discipline {
        case .run: return KXColor.run
        case .strength: return KXColor.lift
        default: return KXColor.other
        }
    }

    // MARK: 3 · Progression

    private var progression: some View {
        let outline = PlanService.generator.makeOutline(for: plan)
        let volumes = outline.weeks.map(\.runVolumeMeters)
        let peak = volumes.max() ?? 1
        return VStack(alignment: .leading, spacing: KXSpacing.lg) {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                Stepper(value: percent($plan.longRunGrowth), in: 0...10) {
                    LabeledContent("Long run grows", value: "+\(Int((plan.longRunGrowth * 100).rounded()))% / week")
                }
                Stepper(value: percent($plan.runGrowth), in: 0...10) {
                    LabeledContent("Other runs grow", value: "+\(Int((plan.runGrowth * 100).rounded()))% / week")
                }
                Picker("Easier week", selection: $plan.deloadEvery) {
                    Text("Never").tag(0)
                    Text("Every 3 weeks").tag(3)
                    Text("Every 4 weeks").tag(4)
                    Text("Every 5 weeks").tag(5)
                }
                if plan.deloadEvery > 0 {
                    Stepper(value: percent($plan.deloadShare), in: 50...90, step: 5) {
                        LabeledContent("Easier week", value: "\(100 - Int((plan.deloadShare * 100).rounded()))% lighter")
                    }
                }
                LabeledContent("Gym weights", value: "Progress as usual")
                Text("Capped so running never grows more than 10% a week.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            .kxCard()

            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                KXOverline("Preview · weekly running")
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(outline.weeks, id: \.index) { week in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(week.phase == .taper ? KXColor.warning : week.isRecoveryWeek ? KXColor.other
                                  : week.runVolumeMeters == peak ? KXColor.accent : KXColor.run)
                            .frame(height: max(6, 120 * week.runVolumeMeters / max(peak, 1)))
                    }
                }
                .frame(height: 120, alignment: .bottom)
                HStack {
                    Text("Wk 1 · \(format.distance(volumes.first ?? 0, decimals: 0))")
                    Spacer()
                    Text("Peak · \(format.distance(peak, decimals: 0))")
                    if plan.hasRace { Spacer(); Text("Race") }
                }
                .font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
            }
            .kxCard()

            Text(isEditing
                 ? "Your changes start next Monday; this week stays as it is."
                 : "Recovery, swaps, moving days and your watch all work as they do with a Kinetix plan. Change it later and the new version starts the following Monday.")
                .font(KXFont.callout).foregroundStyle(KXColor.ink)
                .padding(KXSpacing.md)
                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: KXRadius.sm))
        }
    }

    private func percent(_ value: Binding<Double>) -> Binding<Int> {
        Binding(get: { Int((value.wrappedValue * 100).rounded()) }, set: { value.wrappedValue = Double($0) / 100 })
    }

    private func save() {
        guard let profile = profiles.first?.profile else { return }
        if isEditing {
            PlanService.updateCustomPlan(plan, profile: profile, in: context)
        } else {
            PlanService.createCustomPlan(plan, profile: profile, in: context)
        }
        dismiss()
    }
}

/// Pick a session for a day: saved workouts, Kinetix runs, Kinetix gym sessions or cardio.
private struct AddPlanSessionSheet: View {
    let day: Weekday
    let units: UnitSystem
    let runTemplates: [RunTemplateModel]
    let gymTemplates: [GymTemplateModel]
    let onAdd: (CustomPlan.Item) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var slot: SessionSlot = .morning
    @State private var runType: RunSessionType = .easy
    @State private var meters: Double = 6000

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $tab) {
                        Text("My workouts").tag(0)
                        Text("Runs").tag(1)
                        Text("Gym").tag(2)
                        Text("Other").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Picker("Time", selection: $slot) {
                        Text("Morning").tag(SessionSlot.morning)
                        Text("Evening").tag(SessionSlot.evening)
                    }
                    .pickerStyle(.segmented)
                }
                switch tab {
                case 0: savedWorkouts
                case 1: runTypes
                case 2: gymSessions
                default:
                    Section {
                        Button("Low-impact cardio · 30 min") { add(.crossTraining(minutes: 30)) }
                        Button("Low-impact cardio · 45 min") { add(.crossTraining(minutes: 45)) }
                    }
                }
            }
            .navigationTitle("Add to \(day.fullName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(KXColor.accent)
    }

    @ViewBuilder private var savedWorkouts: some View {
        Section("Run workouts") {
            if runTemplates.isEmpty { Text("None saved yet (Record → build a run → Save).").foregroundStyle(KXColor.inkSecondary) }
            ForEach(runTemplates) { template in
                Button {
                    add(.runWorkout(template.workout))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.workout.name).foregroundStyle(KXColor.ink)
                        if let structure = template.workout.structure, structure.segments.count > 1 {
                            SessionStructureBar(structure: structure).frame(height: 6)
                        }
                    }
                }
            }
        }
        Section("Gym workouts") {
            if gymTemplates.isEmpty { Text("None saved yet (Record → Gym → Save as template).").foregroundStyle(KXColor.inkSecondary) }
            ForEach(gymTemplates) { template in
                Button {
                    add(.gymWorkout(name: template.name, exercises: template.items))
                } label: {
                    LabeledContent(template.name, value: "\(template.items.count) exercises").foregroundStyle(KXColor.ink)
                }
            }
        }
    }

    @ViewBuilder private var runTypes: some View {
        Section {
            Picker("Run", selection: $runType) {
                Text("Easy").tag(RunSessionType.easy)
                Text("Long").tag(RunSessionType.long)
                Text("Recovery").tag(RunSessionType.recovery)
                Text("Tempo").tag(RunSessionType.tempo)
                Text("Intervals").tag(RunSessionType.intervals)
            }
            if runType == .tempo || runType == .intervals {
                Text("Kinetix picks the session each week, getting harder as you go, with your paces.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            } else {
                DistanceField(meters: $meters, units: units)
                Text(runType == .long ? "Week 1 distance: it builds up from here." : "Week 1 distance.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Button("Add \(SessionKind.run(runType).displayName.lowercased())") { add(.run(runType, meters: meters)) }
                .accessibilityIdentifier("builder.addRun")
        }
        .onChange(of: runType) { _, type in
            meters = type == .long ? 14000 : type == .recovery ? 4000 : 6000
        }
    }

    @ViewBuilder private var gymSessions: some View {
        Section("Kinetix gym sessions") {
            ForEach(PlanService.templates.strength.sessions.sorted { $0.value.name < $1.value.name }, id: \.key) { key, template in
                Button(template.name) { add(.gymSession(key)) }.foregroundStyle(KXColor.ink)
            }
        }
    }

    private func add(_ activity: CustomPlan.Activity) {
        onAdd(CustomPlan.Item(weekday: day, slot: slot, activity: activity))
    }
}
