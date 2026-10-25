import SwiftUI
import SwiftData
import TrainingEngine

/// The live strength session: exercises, pre-filled sets, quick logging and rest timer.
struct StrengthWorkoutView: View {
    @State private var model: StrengthWorkoutModel
    let units: UnitSystem
    let onClose: () -> Void
    /// Closes the trainer down to the bar above the tabs; the workout keeps going.
    var onMinimise: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @State private var showFinish = false
    @State private var showLeave = false
    @State private var summary: StrengthService.Summary?
    @State private var showPicker = false
    /// Set just before a discarded workout is deleted, so nothing reads it afterwards.
    @State private var discarded = false

    init(model: StrengthWorkoutModel, units: UnitSystem, onClose: @escaping () -> Void, onMinimise: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.units = units
        self.onClose = onClose
        self.onMinimise = onMinimise
    }

    var body: some View {
        if discarded {
            KXColor.background.ignoresSafeArea()
        } else if let summary {
            StrengthSummaryView(summary: summary, units: units, log: model.log, onDone: onClose)
        } else {
            workout
        }
    }

    private var workout: some View {
        VStack(spacing: 0) {
            header
            if model.needsWarmUp {
                WarmUpPage(model: model, units: units)
            } else {
                exercises
            }
        }
        .background(KXColor.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: model.restFinishedCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.setStartedAt)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView(excluding: model.exerciseIds) { exercise in
                model.addExercise(exercise)
            }
        }
        .sheet(isPresented: $showFinish) {
            FinishWorkoutSheet(defaultEffort: model.planned?.plannedEffort ?? 7, completedSets: model.completedSets, totalSets: model.totalSets) { effort in
                showFinish = false
                model.endSetTimer()
                summary = StrengthService.finish(model.log, planned: model.planned, effort: effort, units: units, in: context)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Leave this workout?", isPresented: $showLeave, titleVisibility: .visible) {
            // Close after the dialog has gone: iOS ignores a dismiss while the dialog is still closing.
            Button("Keep for later") { closeAfterDialog() }
            Button("Discard workout", role: .destructive) {
                discarded = true
                model.endLockScreen()
                let log = model.log
                closeAfterDialog()
                // Delete once the screen has gone, so SwiftUI never draws a deleted workout.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    StrengthService.discard(log, in: context)
                }
            }
        } message: {
            Text("Logged sets are saved, so you can pick up where you left off.")
        }
    }

    private var exercises: some View {
        VStack(spacing: 0) {
            if model.restEndsAt != nil { restBanner }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: KXSpacing.lg) {
                        if model.groups.isEmpty {
                            KXEmptyState(symbol: "dumbbell", title: "No exercises yet",
                                         message: "Add your first exercise. Weights and reps fill in from last time.")
                        }
                        ForEach(model.groups) { group in
                            ExerciseCard(group: group, isCurrent: group.key == model.currentKey, units: units, model: model)
                                .id(group.key)
                        }
                        if model.canEditExercises {
                            Button {
                                showPicker = true
                            } label: {
                                Label("Add exercise", systemImage: "plus")
                            }
                            .buttonStyle(.kx(.secondary, fullWidth: true))
                            .accessibilityIdentifier("gym.addExercise")
                        }
                        if let name = model.savedTemplateName {
                            Label("Saved \u{201C}\(name)\u{201D} to My gym workouts", systemImage: "checkmark.circle.fill")
                                .font(KXFont.callout).foregroundStyle(KXColor.ink)
                                .symbolRenderingMode(.multicolor)
                        }
                    }
                    .padding(KXSpacing.screenMargin)
                }
                .onChange(of: model.currentKey) { _, key in
                    guard let key else { return }
                    withAnimation { proxy.scrollTo(key, anchor: .top) }
                }
            }
            setButton
        }
    }

    /// Start set → Finish set (timed) for the next set; Finish workout once they're all done.
    @ViewBuilder
    private var setButton: some View {
        VStack(spacing: KXSpacing.xs) {
            if model.totalSets > 0, model.nextSet != nil {
                if let summary = model.nextSetSummary {
                    Text(summary)
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .lineLimit(1)
                }
                if let started = model.setStartedAt {
                    Button {
                        model.finishSet()
                    } label: {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text("Finish set · \(Units.formatMinutesSeconds(context.date.timeIntervalSince(started)))")
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.kx(.inverted, fullWidth: true))
                    .accessibilityIdentifier("gym.finishSet")
                } else {
                    Button("Start set") { model.startSet() }
                        .buttonStyle(.kx(.primary, fullWidth: true))
                        .accessibilityIdentifier("gym.startSet")
                }
            } else {
                Button("Finish workout") { showFinish = true }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .disabled(model.totalSets == 0)
            }
        }
        .padding(KXSpacing.screenMargin)
    }

    private func closeAfterDialog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onClose() }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.md) {
            KXIconButton(systemImage: "xmark", accessibilityLabel: "Leave workout", size: 36) { showLeave = true }
            VStack(alignment: .leading, spacing: 0) {
                KXOverline(model.canEditExercises ? "Gym" : "Strength Trainer", color: KXColor.accent)
                Text(model.log.title).font(KXFont.headline).foregroundStyle(KXColor.ink).lineLimit(1)
            }
            Spacer()
            Menu {
                Button {
                    showFinish = true
                } label: {
                    Label("Finish workout", systemImage: "flag.checkered")
                }
                .disabled(model.totalSets == 0)
                if model.canEditExercises {
                    Button {
                        model.saveAsTemplate()
                    } label: {
                        Label("Save as template", systemImage: "bookmark")
                    }
                    .disabled(model.totalSets == 0)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(KXColor.ink)
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("gym.more")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Units.formatMinutesSeconds(context.date.timeIntervalSince(model.log.startedAt)))
                        .font(KXFont.bodyEmphasis.monospacedDigit())
                        .foregroundStyle(KXColor.ink)
                    Text("Active \(Units.formatMinutesSeconds(model.activeSeconds(at: context.date))) · \(model.completedSets)/\(model.totalSets)")
                        .font(KXFont.caption.monospacedDigit())
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            if let onMinimise {
                KXIconButton(systemImage: "chevron.down", accessibilityLabel: "Minimise", size: 36, action: onMinimise)
                    .accessibilityIdentifier("gym.minimise")
            }
        }
        .padding(.horizontal, KXSpacing.screenMargin)
        .padding(.vertical, KXSpacing.sm)
    }

    private var restBanner: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, (model.restEndsAt ?? context.date).timeIntervalSince(context.date))
            HStack(spacing: KXSpacing.md) {
                ZStack {
                    Circle().stroke(KXColor.onInverted.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: model.restTotalSeconds > 0 ? remaining / model.restTotalSeconds : 0)
                        .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 0) {
                    KXOverline(remaining > 0 ? "Rest" : "Rest done · start when ready", color: KXColor.onInverted.opacity(0.7))
                    Text(Units.formatMinutesSeconds(remaining))
                        .font(KXFont.metricSmall)
                        .foregroundStyle(KXColor.onInverted)
                }
                Spacer()
                Button("+15s") { model.extendRest(by: 15) }
                    .buttonStyle(.kx(.outlined))
                    .environment(\.colorScheme, .dark)
                Button("Skip") { model.skipRest() }
                    .buttonStyle(.kx(.primary))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rest, \(Int(remaining)) seconds remaining")
        }
        .padding(KXSpacing.md)
        .background(KXColor.inverted)
    }
}

/// One exercise with its sets. Finished sets fold to one line (tap to open); a finished
/// exercise folds to its name and a summary. The set just finished stays open for its
/// effort rating until the next set starts.
private struct ExerciseCard: View {
    let group: StrengthWorkoutModel.ExerciseGroup
    let isCurrent: Bool
    let units: UnitSystem
    let model: StrengthWorkoutModel

    @State private var openSets: Set<UUID> = []
    @State private var exerciseOpen = false

    private var format: DisplayFormat { DisplayFormat(units: units) }

    private var holdsLastFinished: Bool {
        guard let id = model.lastFinishedSetId else { return false }
        return group.sets.contains { $0.id == id }
    }

    private var isFolded: Bool { group.isComplete && !exerciseOpen && !holdsLastFinished }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(group.name).font(KXFont.headline).foregroundStyle(KXColor.ink)
                    if isFolded {
                        Text(doneSummary).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    } else {
                        Text(targetText).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        if let lastTime = model.lastTime[group.first.exerciseId] {
                            Label(lastTime, systemImage: "clock.arrow.circlepath")
                                .font(KXFont.caption)
                                .foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                }
                Spacer()
                if group.isComplete {
                    KXChip(text: "Done", systemImage: "checkmark", variant: .success)
                } else if isCurrent {
                    KXChip(text: "Now", variant: .primary)
                }
                if group.isComplete {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { exerciseOpen.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KXColor.inkSecondary)
                            .rotationEffect(.degrees(isFolded ? 0 : 180))
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(isFolded ? "Show sets" : "Hide sets")
                }
                if model.canEditExercises {
                    Menu {
                        Button(role: .destructive) {
                            model.removeExercise(group)
                        } label: {
                            Label("Remove exercise", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(KXColor.inkSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Options for \(group.name)")
                }
            }
            if !isFolded {
                ForEach(group.sets) { set in
                    if set.isCompleted && set.id != model.lastFinishedSetId && !openSets.contains(set.id) {
                        DoneSetRow(set: set, units: units) {
                            withAnimation(.easeInOut(duration: 0.2)) { _ = openSets.insert(set.id) }
                        }
                    } else {
                        SetRow(set: set, units: units, model: model)
                            .onChange(of: set.isCompleted) { _, done in if !done { openSets.remove(set.id) } }
                    }
                }
                Button {
                    model.addSet(to: group)
                } label: {
                    Label("Add set", systemImage: "plus")
                        .font(KXFont.captionEmphasis)
                }
                .foregroundStyle(KXColor.accent)
            }
        }
        .kxCard(isCurrent ? .raised : .tinted)
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .strokeBorder(isCurrent ? KXColor.accent : .clear, lineWidth: 1.5)
        }
    }

    private var targetText: String {
        let first = group.first
        let reps = "\(group.sets.count) × \(first.repRangeLower)–\(first.repRangeUpper)"
        let load = first.isBodyweight ? "bodyweight" : format.weight(first.targetWeightKg)
        return "Target \(reps) @ \(load) · rest \(Units.formatMinutesSeconds(Double(first.restSeconds)))"
    }

    /// "3 sets · 60 kg × 8, 8, 7"
    private var doneSummary: String {
        let done = group.sets.filter(\.isCompleted)
        let reps = done.map { "\($0.actualReps)" }.joined(separator: ", ")
        let weights = Set(done.map(\.actualWeightKg))
        let load: String
        if group.first.isBodyweight { load = "bodyweight" }
        else if weights.count == 1, let w = weights.first { load = format.weight(w) }
        else { load = "up to " + format.weight(weights.max() ?? 0) }
        return "\(done.count) set\(done.count == 1 ? "" : "s") · \(load) × \(reps)"
    }
}

/// A finished set on one line: "1 · 60 kg × 8 · RPE 8 ✓". Tap to change it.
private struct DoneSetRow: View {
    let set: SetLogModel
    let units: UnitSystem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: KXSpacing.sm) {
                Text("\(set.setIndex + 1)")
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.inkSecondary)
                    .frame(width: 20)
                Text(set.isBodyweight ? "\(set.actualReps) reps"
                     : "\(DisplayFormat(units: units).weight(set.actualWeightKg)) × \(set.actualReps)")
                    .font(KXFont.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(KXColor.ink)
                if let rpe = set.rpe {
                    Text("RPE \(Int(rpe))").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                if let seconds = set.activeSeconds {
                    Text(Units.formatMinutesSeconds(seconds)).font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkTertiary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(KXColor.success)
            }
            .padding(.horizontal, KXSpacing.sm)
            .padding(.vertical, KXSpacing.xs)
            .background(KXColor.success.opacity(0.08), in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(set.setIndex + 1) done, \(set.actualReps) reps")
        .accessibilityHint("Opens the set to change it")
    }
}

/// A set: weight and reps pre-filled with targets, tap to adjust, tick to complete.
private struct SetRow: View {
    let set: SetLogModel
    let units: UnitSystem
    let model: StrengthWorkoutModel

    private var weightStep: Double { units == .metric ? 2.5 : Units.lbToKg(5) }

    var body: some View {
        VStack(spacing: KXSpacing.sm) {
            HStack(spacing: KXSpacing.sm) {
                Text("\(set.setIndex + 1)")
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.inkSecondary)
                    .frame(width: 20)
                if set.isBodyweight {
                    Text("Bodyweight")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(maxWidth: .infinity)
                } else {
                    CompactStepper(
                        value: Units.formatWeight(kg: set.actualWeightKg, units: units),
                        unit: Units.weightUnitLabel(units),
                        label: "Set \(set.setIndex + 1) weight",
                        allowsDecimal: true,
                        onMinus: { model.update(set, weight: set.actualWeightKg - weightStep) },
                        onPlus: { model.update(set, weight: set.actualWeightKg + weightStep) },
                        onType: { typed in model.update(set, weight: max(0, units == .metric ? typed : Units.lbToKg(typed))) }
                    )
                }
                CompactStepper(
                    value: "\(set.actualReps)",
                    unit: "reps",
                    label: "Set \(set.setIndex + 1) reps",
                    allowsDecimal: false,
                    onMinus: { model.update(set, reps: set.actualReps - 1) },
                    onPlus: { model.update(set, reps: set.actualReps + 1) },
                    onType: { typed in model.update(set, reps: max(0, Int(typed))) }
                )
                Button {
                    model.toggleComplete(set)
                } label: {
                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 30))
                        .foregroundStyle(set.isCompleted ? KXColor.success : KXColor.border)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isCompleted ? "Set \(set.setIndex + 1) done. Tap to undo" : "Complete set \(set.setIndex + 1)")
            }
            if set.isCompleted {
                RPEPicker(value: set.rpe) { model.setRPE($0, for: set) }
            }
        }
        .padding(KXSpacing.sm)
        .background(set.isCompleted ? KXColor.success.opacity(0.08) : KXColor.surfaceTint,
                    in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
    }
}

/// "– 105 kg +" in a compact row. Tap the number to type it.
private struct CompactStepper: View {
    let value: String
    let unit: String
    let label: String
    var allowsDecimal = false
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onType: (Double) -> Void

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", action: onMinus)
            VStack(spacing: 0) {
                KXEditableNumber(display: value, font: KXFont.bodyEmphasis, allowsDecimal: allowsDecimal,
                                 accessibilityLabel: label, onCommit: onType)
                Text(unit).font(.caption2).foregroundStyle(KXColor.inkSecondary)
            }
            .frame(minWidth: 48)
            stepButton("plus", action: onPlus)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onPlus()
            case .decrement: onMinus()
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(KXColor.ink)
                .frame(width: 32, height: 32)
                .background(KXColor.surface, in: Circle())
                // Larger touch target around the 32 pt circle (kept compact so two steppers fit a small iPhone).
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Optional effort rating for a set (RPE 6-10; tap again to clear).
private struct RPEPicker: View {
    let value: Double?
    let onChange: (Double?) -> Void

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            Text("Effort (RPE)")
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkSecondary)
            Spacer()
            ForEach(6...10, id: \.self) { rpe in
                let selected = value == Double(rpe)
                Button("\(rpe)") { onChange(selected ? nil : Double(rpe)) }
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(selected ? KXColor.onAccent : KXColor.ink)
                    .frame(width: 32, height: 28)
                    .background(selected ? KXColor.accent : KXColor.surface, in: Capsule())
                    .buttonStyle(.plain)
                    .accessibilityLabel("RPE \(rpe)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Asks for overall session effort (sRPE), then finishes.
private struct FinishWorkoutSheet: View {
    @State private var effort: Double
    let completedSets: Int
    let totalSets: Int
    let onFinish: (Double) -> Void

    init(defaultEffort: Double, completedSets: Int, totalSets: Int, onFinish: @escaping (Double) -> Void) {
        _effort = State(initialValue: min(max(defaultEffort.rounded(), 1), 10))
        self.completedSets = completedSets
        self.totalSets = totalSets
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text("How hard was that overall?").font(KXFont.title).foregroundStyle(KXColor.ink)
                Text("Your effort rating feeds your training load, which balances running and lifting.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            VStack(spacing: KXSpacing.sm) {
                HStack {
                    Text("\(Int(effort))").font(KXFont.metric).foregroundStyle(KXColor.accent)
                    Text("/ 10 · \(Self.label(for: effort))").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Spacer()
                }
                Slider(value: $effort, in: 1...10, step: 1)
                    .tint(KXColor.accent)
                    .accessibilityLabel("Session effort")
                    .accessibilityValue("\(Int(effort)) out of 10, \(Self.label(for: effort))")
            }
            if completedSets < totalSets {
                Label("\(totalSets - completedSets) set\(totalSets - completedSets == 1 ? "" : "s") not ticked off. They'll count as missed.",
                      systemImage: "exclamationmark.circle")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.warning)
            }
            Button("Save workout") { onFinish(effort) }
                .buttonStyle(.kx(.primary, fullWidth: true))
        }
        .padding(KXSpacing.xl)
    }

    static func label(for effort: Double) -> String {
        switch Int(effort) {
        case ...2: return "Very easy"
        case 3...4: return "Easy"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        case 9: return "Very hard"
        default: return "Maximal"
        }
    }
}

/// Before the first set: a warm-up timer counting up, what's first, and "Start first set".
private struct WarmUpPage: View {
    let model: StrengthWorkoutModel
    let units: UnitSystem

    var body: some View {
        VStack(spacing: KXSpacing.xl) {
            Spacer()
            VStack(spacing: KXSpacing.sm) {
                KXOverline("Warm-up", color: KXColor.accent)
                TimelineView(.periodic(from: model.warmUpStartedAt, by: 1)) { context in
                    Text(Units.formatMinutesSeconds(context.date.timeIntervalSince(model.warmUpStartedAt)))
                        .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(KXColor.ink)
                        .accessibilityLabel("Warm-up time \(Int(context.date.timeIntervalSince(model.warmUpStartedAt) / 60)) minutes")
                }
                Text("A few minutes of easy cardio, then lighter sets of your first lift.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            if let first = model.groups.first {
                VStack(spacing: KXSpacing.xxs) {
                    Text("First up").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    Text(first.name).font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text("\(first.sets.count) × \(first.first.repRangeLower)–\(first.first.repRangeUpper)"
                         + (first.first.isBodyweight ? "" : " @ \(DisplayFormat(units: units).weight(first.first.targetWeightKg))"))
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .kxCard(.tinted)
            }
            Spacer()
            VStack(spacing: KXSpacing.sm) {
                Button("Start first set") { model.finishWarmUp(startFirstSet: true) }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .accessibilityIdentifier("gym.startFirstSet")
                Button("Skip warm-up") { model.finishWarmUp(startFirstSet: false) }
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.inkSecondary)
            }
        }
        .padding(KXSpacing.screenMargin)
    }
}
