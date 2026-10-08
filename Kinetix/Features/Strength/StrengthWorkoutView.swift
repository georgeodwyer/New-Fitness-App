import SwiftUI
import SwiftData
import TrainingEngine

/// The live strength session: exercises, pre-filled sets, quick logging and rest timer.
struct StrengthWorkoutView: View {
    @State private var model: StrengthWorkoutModel
    let units: UnitSystem
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showFinish = false
    @State private var showLeave = false
    @State private var summary: StrengthService.Summary?

    init(model: StrengthWorkoutModel, units: UnitSystem, onClose: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.units = units
        self.onClose = onClose
    }

    var body: some View {
        if let summary {
            StrengthSummaryView(summary: summary, units: units, onDone: onClose)
        } else {
            workout
        }
    }

    private var workout: some View {
        VStack(spacing: 0) {
            header
            if model.restEndsAt != nil { restBanner }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: KXSpacing.lg) {
                        ForEach(model.groups) { group in
                            ExerciseCard(group: group, isCurrent: group.key == model.currentKey, units: units, model: model)
                                .id(group.key)
                        }
                    }
                    .padding(KXSpacing.screenMargin)
                }
                .onChange(of: model.currentKey) { _, key in
                    guard let key else { return }
                    withAnimation { proxy.scrollTo(key, anchor: .top) }
                }
            }
            Button("Finish workout") { showFinish = true }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: model.restFinishedCount)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showFinish) {
            FinishWorkoutSheet(defaultEffort: model.planned?.plannedEffort ?? 7, completedSets: model.completedSets, totalSets: model.totalSets) { effort in
                showFinish = false
                summary = StrengthService.finish(model.log, planned: model.planned, effort: effort, units: units, in: context)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Leave this workout?", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Keep for later") { onClose() }
            Button("Discard workout", role: .destructive) {
                StrengthService.discard(model.log, in: context)
                onClose()
            }
        } message: {
            Text("Logged sets are saved, so you can pick up where you left off.")
        }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.md) {
            KXIconButton(systemImage: "xmark", accessibilityLabel: "Leave workout", size: 36) { showLeave = true }
            VStack(alignment: .leading, spacing: 0) {
                KXOverline("Strength Trainer", color: KXColor.accent)
                Text(model.log.title).font(KXFont.headline).foregroundStyle(KXColor.ink).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Units.formatMinutesSeconds(context.date.timeIntervalSince(model.log.startedAt)))
                        .font(KXFont.bodyEmphasis.monospacedDigit())
                        .foregroundStyle(KXColor.ink)
                }
                Text("\(model.completedSets)/\(model.totalSets) sets").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            .accessibilityElement(children: .combine)
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
                    KXOverline("Rest", color: KXColor.onInverted.opacity(0.7))
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

/// One exercise with its sets.
private struct ExerciseCard: View {
    let group: StrengthWorkoutModel.ExerciseGroup
    let isCurrent: Bool
    let units: UnitSystem
    let model: StrengthWorkoutModel

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(group.name).font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text(targetText).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
                if group.isComplete {
                    KXChip(text: "Done", systemImage: "checkmark", variant: .success)
                } else if isCurrent {
                    KXChip(text: "Now", variant: .primary)
                }
            }
            ForEach(group.sets) { set in
                SetRow(set: set, units: units, model: model)
            }
            Button {
                model.addSet(to: group)
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(KXFont.captionEmphasis)
            }
            .foregroundStyle(KXColor.accent)
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
                        onMinus: { model.update(set, weight: set.actualWeightKg - weightStep) },
                        onPlus: { model.update(set, weight: set.actualWeightKg + weightStep) }
                    )
                }
                CompactStepper(
                    value: "\(set.actualReps)",
                    unit: "reps",
                    label: "Set \(set.setIndex + 1) reps",
                    onMinus: { model.update(set, reps: set.actualReps - 1) },
                    onPlus: { model.update(set, reps: set.actualReps + 1) }
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

/// "– 105 kg +" in a compact row.
private struct CompactStepper: View {
    let value: String
    let unit: String
    let label: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            stepButton("minus", action: onMinus)
            VStack(spacing: 0) {
                Text(value).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
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
