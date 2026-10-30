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
    @State private var swapGroup: StrengthWorkoutModel.ExerciseGroup?
    /// 0 = exercises, 1 = heart rate.
    @State private var page = 0
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
        .sheet(item: $swapGroup) { group in
            SwapExerciseSheet(current: group, equipment: model.equipment, excluding: model.exerciseIds) { exercise in
                model.swap(group, to: exercise)
            }
        }
        .alert(keepTitle, isPresented: Binding(get: { model.pendingKeep != nil }, set: { if !$0 { model.pendingKeep = nil } }),
               presenting: model.pendingKeep) { _ in
            Button("Keep it") { model.keepSwap() }
            Button("Just today", role: .cancel) { model.pendingKeep = nil }
        } message: { pending in
            Text(keepMessage(pending))
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
            // Swipe left for heart rate.
            TabView(selection: $page) {
                exerciseList.tag(0)
                GymHeartRatePage(model: model).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            setButton
        }
    }

    private var exerciseList: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: KXSpacing.lg) {
                        if model.groups.isEmpty {
                            KXEmptyState(symbol: "dumbbell", title: "No exercises yet",
                                         message: "Add your first exercise. Weights and reps fill in from last time.")
                        }
                        ForEach(model.groups) { group in
                            ExerciseCard(group: group, isCurrent: group.key == model.currentKey, units: units, model: model,
                                         onSwap: { swapGroup = group })
                                .id(group.key)
                                // Press and hold to drag an exercise into a new place.
                                .draggable(group.key) {
                                    Label(group.name, systemImage: "line.3.horizontal")
                                        .font(KXFont.bodyEmphasis)
                                        .padding(KXSpacing.md)
                                        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md))
                                }
                                .dropDestination(for: String.self) { keys, _ in
                                    guard let key = keys.first, key != group.key else { return false }
                                    withAnimation { model.move(key, before: group.key) }
                                    return true
                                }
                        }
                        if model.groups.count > 1 {
                            // Drop here to move an exercise to the end.
                            Text("Hold and drag an exercise to change the order")
                                .font(KXFont.caption)
                                .foregroundStyle(KXColor.inkTertiary)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .dropDestination(for: String.self) { keys, _ in
                                    guard let key = keys.first else { return false }
                                    withAnimation { model.move(key, before: nil) }
                                    return true
                                }
                        }
                        if let message = model.keptMessage {
                            Label(message, systemImage: "checkmark.circle.fill")
                                .font(KXFont.callout).foregroundStyle(KXColor.ink)
                                .symbolRenderingMode(.multicolor)
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
                    .padding(.bottom, KXSpacing.xl)
                }
                .onChange(of: model.currentKey) { _, key in
                    guard let key else { return }
                    withAnimation { proxy.scrollTo(key, anchor: .top) }
                }
            }
    }

    /// Start set → Finish set (timed) for the next set; Finish workout once they're all done.
    @ViewBuilder
    private var setButton: some View {
        HStack(spacing: KXSpacing.sm) {
            if model.canUndo {
                Button { model.undoLast() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold))
                }
                .buttonStyle(.kx(.outlined))
                .fixedSize()
                .accessibilityLabel(model.undoLabel)
                .accessibilityIdentifier("gym.undo")
            }
            mainSetButton
        }
        .padding(KXSpacing.screenMargin)
    }

    private var mainSetButton: some View {
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
                // Short on time: save what's done; the sets left count as missed.
                if model.completedSets > 0 {
                    Button("Finish early · \(model.completedSets) of \(model.totalSets) sets done") { showFinish = true }
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                        .padding(.top, KXSpacing.xxs)
                        .accessibilityIdentifier("gym.finishEarly")
                }
            } else {
                Button("Finish workout") { showFinish = true }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .disabled(model.totalSets == 0)
            }
        }
    }

    private var keepTitle: String { model.pendingKeep.map { "Keep \($0.to.name)?" } ?? "" }

    private func keepMessage(_ pending: StrengthWorkoutModel.PendingKeep) -> String {
        switch pending.target {
        case .planDay(let day):
            return "Use \(pending.to.name) instead of \(pending.fromName) in every \(day) session from now on?"
        case .savedWorkout(let name):
            return "Save \(pending.to.name) instead of \(pending.fromName) in \u{201C}\(name)\u{201D}?"
        }
    }

    private func closeAfterDialog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onClose() }
    }

    private var header: some View {
        VStack(spacing: KXSpacing.xs) {
            HStack(spacing: KXSpacing.sm) {
                KXIconButton(systemImage: "xmark", accessibilityLabel: "Leave workout", size: 36) { showLeave = true }
                VStack(alignment: .leading, spacing: 0) {
                    KXOverline((model.canEditExercises ? "Gym" : "Strength") + " · live", color: KXColor.lift)
                    Text(model.log.title).font(KXFont.headline).textCase(.uppercase).foregroundStyle(KXColor.ink)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: KXSpacing.xs)
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
                if let onMinimise {
                    KXIconButton(systemImage: "chevron.down", accessibilityLabel: "Minimise", size: 36, action: onMinimise)
                        .accessibilityIdentifier("gym.minimise")
                }
            }
            // Time, heart rate and progress on their own line, so they always fit.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
                    Text(Units.formatMinutesSeconds(context.date.timeIntervalSince(model.log.startedAt)))
                        .font(KXFont.number(28, relativeTo: .title2))
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(1)
                        .fixedSize()
                    if let bpm = model.currentHeartRate(at: context.date) {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(KXFont.caption).foregroundStyle(KXColor.danger)
                            Text("\(Int(bpm))").font(KXFont.number(17, relativeTo: .body)).foregroundStyle(KXColor.ink)
                        }
                        .fixedSize()
                        .accessibilityLabel("Heart rate \(Int(bpm))")
                    }
                    Spacer(minLength: KXSpacing.xs)
                    Text("Active \(Units.formatMinutesSeconds(model.activeSeconds(at: context.date))) · \(model.completedSets)/\(model.totalSets) sets")
                        .font(KXFont.caption.monospacedDigit())
                        .foregroundStyle(KXColor.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, KXSpacing.screenMargin)
        .padding(.vertical, KXSpacing.sm)
    }

    /// Rest countdown: a card inside the screen margins, in the normal card colours so it
    /// sits right in light and dark mode.
    private var restBanner: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, (model.restEndsAt ?? context.date).timeIntervalSince(context.date))
            HStack(spacing: KXSpacing.sm) {
                ZStack {
                    Circle().stroke(KXColor.border, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: model.restTotalSeconds > 0 ? remaining / model.restTotalSeconds : 0)
                        .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    KXOverline(remaining > 0 ? "Rest" : "Rest done", color: KXColor.inkSecondary)
                    Text(remaining > 0 ? Units.formatMinutesSeconds(remaining) : "Start when ready")
                        .font(remaining > 0 ? KXFont.metricSmall : KXFont.bodyEmphasis)
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)
                Spacer(minLength: KXSpacing.xs)
                Button("+15s") { model.extendRest(by: 15) }
                    .buttonStyle(.kx(.outlined))
                    .fixedSize()
                Button("Skip") { model.skipRest() }
                    .buttonStyle(.kx(.primary))
                    .fixedSize()
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rest, \(Int(remaining)) seconds remaining")
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.sm)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).strokeBorder(KXColor.accent.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, KXSpacing.screenMargin)
        .padding(.vertical, KXSpacing.xs)
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
    let onSwap: () -> Void

    @State private var openSets: Set<UUID> = []
    /// Their own open/closed choice for this card (nil = automatic: folded once done).
    @State private var folded: Bool?

    private var format: DisplayFormat { DisplayFormat(units: units) }

    private var holdsLastFinished: Bool {
        guard let id = model.lastFinishedSetId else { return false }
        return group.sets.contains { $0.id == id }
    }

    private var isFolded: Bool { folded ?? (group.isComplete && !holdsLastFinished) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(group.name).font(KXFont.headline).textCase(.uppercase).foregroundStyle(KXColor.ink)
                    if isFolded {
                        Text(group.isComplete ? doneSummary : targetText).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
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
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { folded = !isFolded }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                        .rotationEffect(.degrees(isFolded ? 0 : 180))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(isFolded ? "Show sets" : "Hide sets")
                Menu {
                    if !group.isComplete {
                        Button(action: onSwap) {
                            Label("Swap exercise", systemImage: "arrow.left.arrow.right")
                        }
                    }
                    if model.canEditExercises {
                        Button(role: .destructive) {
                            model.removeExercise(group)
                        } label: {
                            Label("Remove exercise", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Options for \(group.name)")
            }
            if !isFolded {
                ForEach(group.sets) { set in
                    if set.isCompleted && set.id != model.lastFinishedSetId && !openSets.contains(set.id) {
                        DoneSetRow(set: set, units: units) {
                            withAnimation(.easeInOut(duration: 0.2)) { _ = openSets.insert(set.id) }
                        }
                        .contextMenu { removeSetButton(set) }
                    } else {
                        SetRow(set: set, units: units, model: model,
                               isNext: isCurrent && set.id == group.sets.first(where: { !$0.isCompleted })?.id,
                               onCollapse: {
                                   withAnimation(.easeInOut(duration: 0.2)) {
                                       _ = openSets.remove(set.id)
                                       model.closeFinishedSet(set)
                                   }
                               })
                            .onChange(of: set.isCompleted) { _, done in if !done { openSets.remove(set.id) } }
                            .contextMenu { removeSetButton(set) }
                    }
                }
                HStack {
                    Button {
                        model.addSet(to: group)
                    } label: {
                        Label("Add set", systemImage: "plus")
                            .font(KXFont.captionEmphasis)
                    }
                    .foregroundStyle(KXColor.accent)
                    Spacer()
                    // Takes off the last set still to do (or the last set, if all are done).
                    if group.sets.count > 1, let set = group.sets.last(where: { !$0.isCompleted }) ?? group.sets.last {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { model.removeSet(set, from: group) }
                        } label: {
                            Label("Remove set", systemImage: "minus")
                                .font(KXFont.captionEmphasis)
                        }
                        .foregroundStyle(KXColor.inkSecondary)
                        .accessibilityIdentifier("gym.removeSet")
                    }
                }
            }
        }
        .kxCard(isCurrent ? .raised : .tinted)
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .strokeBorder(isCurrent ? KXColor.accent : .clear, lineWidth: 1.5)
        }
        // Done (or started again): back to folding by itself, with any opened sets closed.
        .onChange(of: group.isComplete) { _, _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                folded = nil
                openSets.removeAll()
            }
        }
        .onChange(of: isCurrent) { _, current in
            if current { withAnimation(.easeInOut(duration: 0.2)) { folded = nil } }
        }
    }

    @ViewBuilder
    private func removeSetButton(_ set: SetLogModel) -> some View {
        if group.sets.count > 1 {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { model.removeSet(set, from: group) }
            } label: {
                Label("Remove set \(set.setIndex + 1)", systemImage: "trash")
            }
        }
    }

    private var targetText: String {
        let first = group.first
        let reps = "\(group.sets.count) × \(first.repRangeLower)–\(first.repRangeUpper)"
        let load = first.isBodyweight ? "bodyweight" : format.load(first.targetWeightKg)
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
    /// The set to do next: outlined in the accent colour.
    var isNext = false
    /// A finished set that's open: folds it back to one line.
    var onCollapse: (() -> Void)? = nil

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
                        .foregroundStyle(set.isCompleted ? KXColor.success : isNext ? KXColor.accent : KXColor.border)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isCompleted ? "Set \(set.setIndex + 1) done. Tap to undo" : "Complete set \(set.setIndex + 1)")
            }
            if set.isCompleted {
                HStack(spacing: KXSpacing.xs) {
                    RPEPicker(value: set.rpe) { model.setRPE($0, for: set) }
                    if let onCollapse {
                        Button(action: onCollapse) {
                            Image(systemName: "chevron.up")
                                .font(KXFont.captionEmphasis)
                                .foregroundStyle(KXColor.inkSecondary)
                                .frame(width: 32, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fold set \(set.setIndex + 1)")
                    }
                }
            }
        }
        .padding(KXSpacing.sm)
        .background(set.isCompleted ? KXColor.success.opacity(0.08) : isNext ? KXColor.accentSoft : KXColor.surfaceTint,
                    in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous)
                .strokeBorder(isNext ? KXColor.accent : .clear, lineWidth: 1.5)
        }
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
                Text(unit).font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary)
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
                Label("\(totalSets - completedSets) set\(totalSets - completedSets == 1 ? "" : "s") not done. They're left out of your volume and weights only progress on what you finished.",
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
                        .font(KXFont.number(72))
                        .foregroundStyle(KXColor.ink)
                        .accessibilityLabel("Warm-up time \(Int(context.date.timeIntervalSince(model.warmUpStartedAt) / 60)) minutes")
                }
                Text("A few minutes of easy cardio, then lighter sets of your first lift.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                    .multilineTextAlignment(.center)
                warmUpHeartRate
            }
            if let first = model.groups.first {
                VStack(spacing: KXSpacing.xxs) {
                    Text("First up").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    Text(first.name).font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text("\(first.sets.count) × \(first.first.repRangeLower)–\(first.first.repRangeUpper)"
                         + (first.first.isBodyweight ? "" : " @ \(DisplayFormat(units: units).load(first.first.targetWeightKg))"))
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

extension WarmUpPage {
    /// Live heart rate while warming up, with its zone (or where it'll come from).
    var warmUpHeartRate: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let bpm = model.currentHeartRate(at: context.date)
            let zone = bpm.map { model.zones.zone(for: $0) } ?? 0
            HStack(spacing: KXSpacing.sm) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(bpm == nil ? KXColor.inkTertiary : KXColor.danger)
                    .symbolEffect(.pulse, isActive: bpm != nil)
                if let bpm {
                    Text("\(Int(bpm.rounded()))")
                        .font(KXFont.number(28, relativeTo: .title2))
                        .foregroundStyle(KXColor.ink)
                        .contentTransition(.numericText())
                    Text(zone > 0 ? "bpm · Zone \(zone)" : "bpm")
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                } else {
                    Text(model.watchNeedsOpening ? "Open Kinetix on your Apple Watch for heart rate"
                         : model.isOnWatch ? "Waiting for your Apple Watch…" : "No heart rate yet")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .padding(.horizontal, KXSpacing.md)
            .padding(.vertical, KXSpacing.xs)
            .background(KXColor.surface, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gym.warmUpHeartRate")
            if bpm == nil, model.canReconnectWatch {
                ReconnectWatchButton(model: model)
            }
        }
        .padding(.top, KXSpacing.sm)
    }
}

/// Opens Kinetix on the Apple Watch again (it was closed there, so heart rate stopped).
private struct ReconnectWatchButton: View {
    let model: StrengthWorkoutModel
    @State private var asked = false

    var body: some View {
        Button {
            model.reconnectWatch()
            asked = true
            Task {
                try? await Task.sleep(for: .seconds(8))
                asked = false
            }
        } label: {
            Label(asked ? "Opening on your watch…" : "Reconnect Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                .font(KXFont.captionEmphasis)
        }
        .buttonStyle(.kx(.outlined))
        .disabled(asked)
        .accessibilityIdentifier("gym.reconnectWatch")
    }
}

/// "Swap exercise": close matches for the runner's equipment first, then every exercise.
private struct SwapExerciseSheet: View {
    let current: StrengthWorkoutModel.ExerciseGroup
    let equipment: Equipment
    let excluding: Set<String>
    let onPick: (ExerciseDefinition) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var suggestions: [ExerciseDefinition] {
        PlanService.templates.alternatives(to: current.first.exerciseId, equipment: equipment)
            .filter { !excluding.contains($0.id) }
    }

    private var all: [ExerciseDefinition] {
        ExerciseSearch.filter(GymService.library(in: context), query: query, muscle: nil, loading: nil)
            .filter { !excluding.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, !suggestions.isEmpty {
                    Section("Close matches") {
                        ForEach(suggestions, id: \.id) { row($0) }
                    }
                }
                Section(query.isEmpty ? "All exercises" : "Results") {
                    ForEach(all, id: \.id) { row($0) }
                    if all.isEmpty {
                        Text("No exercises match.").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Swap \(current.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(KXColor.accent)
    }

    private func row(_ exercise: ExerciseDefinition) -> some View {
        Button {
            onPick(exercise)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(KXFont.body).foregroundStyle(KXColor.ink)
                Text("\(exercise.muscleGroup.displayName) · \(exercise.loading.displayName)")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gym.swap.\(exercise.id)")
    }
}

/// The second page: live heart rate in the middle, the five zones below with a marker for
/// where you are, and time in each zone this session.
private struct GymHeartRatePage: View {
    let model: StrengthWorkoutModel

    private static let colors: [Color] = [KXColor.slate, KXColor.teal, KXColor.success, KXColor.warning, KXColor.danger]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let bpm = model.currentHeartRate(at: context.date)
            let zone = bpm.map { model.zones.zone(for: $0) } ?? 0
            VStack(spacing: KXSpacing.xl) {
                Spacer(minLength: KXSpacing.md)
                VStack(spacing: KXSpacing.xs) {
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(bpm == nil ? KXColor.inkTertiary : KXColor.danger)
                        .symbolEffect(.pulse, isActive: bpm != nil)
                    Text(bpm.map { "\(Int($0.rounded()))" } ?? "--")
                        .font(KXFont.number(88))
                        .foregroundStyle(KXColor.ink)
                        .contentTransition(.numericText())
                    Text(zone > 0 ? "Zone \(zone) · \(HeartRateZones.names[zone - 1])" : (bpm == nil ? "No heart rate yet" : "Below zone 1"))
                        .font(KXFont.headline)
                        .foregroundStyle(zone > 0 ? Self.colors[zone - 1] : KXColor.inkSecondary)
                    Text(sourceText)
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                if bpm == nil || model.heartRateSource == .health, model.canReconnectWatch {
                    ReconnectWatchButton(model: model)
                }
                Spacer(minLength: KXSpacing.md)
                zoneBar(bpm: bpm)
                timeInZones
            }
            .padding(KXSpacing.screenMargin)
            .padding(.bottom, KXSpacing.xl)
        }
    }

    private var sourceText: String {
        switch model.heartRateSource {
        case .strap?: return "From your chest strap"
        case .watch?: return "From Kinetix on your Apple Watch"
        case .health?: return "From Apple Health (may lag a little)"
        case nil:
            if model.watchNeedsOpening { return "Open Kinetix on your Apple Watch to see your heart rate" }
            return model.isOnWatch ? "Waiting for your Apple Watch…" : "Wear your Apple Watch with Kinetix on it, or pair a chest strap in Settings"
        }
    }

    /// Five coloured zones with a marker at the current heart rate.
    private func zoneBar(bpm: Double?) -> some View {
        let high = model.zones.maxHeartRate
        let starts = model.zones.starts.count == 5 ? model.zones.starts : HeartRateZones.startShares.map { $0 * high }
        let low = starts.first ?? 90
        return VStack(spacing: KXSpacing.xs) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            let from = starts[index]
                            let to = index < 4 ? starts[index + 1] : high
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Self.colors[index])
                                .frame(width: max(0, width * (to - from) / max(1, high - low) - 2))
                        }
                    }
                    if let bpm {
                        let x = width * min(max((bpm - low) / max(1, high - low), 0), 1)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.ink)
                            .offset(x: x - 6, y: -16)
                            .animation(.easeInOut, value: bpm)
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Text("Z\(index + 1)")
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, KXSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate zones")
    }

    private var timeInZones: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { zone in
                VStack(spacing: 2) {
                    Text(Units.formatMinutesSeconds(model.secondsInZone[zone]))
                        .font(KXFont.captionEmphasis.monospacedDigit())
                        .foregroundStyle(KXColor.ink)
                    Text(model.zones.starts.indices.contains(zone - 1) ? "\(Int(model.zones.starts[zone - 1]))+" : "")
                        .font(KXFont.caption2)
                        .foregroundStyle(KXColor.inkTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time in each zone this session")
    }
}
