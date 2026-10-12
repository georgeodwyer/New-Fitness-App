import SwiftUI
import TrainingEngine

/// Builds a custom run: blocks of steps (warm-up, work, recovery, cool-down), each set by
/// distance or time, with repeats and an optional pace target (single pace or range).
struct WorkoutBuilderView: View {
    @Binding var workout: CustomRunWorkout
    let units: UnitSystem
    let defaultPace: Pace

    @State private var editing: StepLocation?

    struct StepLocation: Identifiable {
        let block: Int
        let step: Int
        var id: String { "\(block)-\(step)" }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Total", value: totals)
                    .accessibilityIdentifier("builder.total")
            } footer: {
                Text("Tap a step to change its length or pace. A repeat block runs all its steps in order, that many times.")
            }

            ForEach(Array(workout.blocks.enumerated()), id: \.element.id) { blockIndex, block in
                Section {
                    if block.steps.contains(where: { $0.kind == .work }) || block.repeats > 1 {
                        Stepper(value: repeatsBinding(blockIndex), in: 1...40) {
                            Label("Repeat \(block.repeats)×", systemImage: "repeat")
                        }
                        .accessibilityIdentifier("builder.repeats.\(blockIndex)")
                    }
                    ForEach(Array(block.steps.enumerated()), id: \.element.id) { stepIndex, step in
                        Button {
                            editing = StepLocation(block: blockIndex, step: stepIndex)
                        } label: {
                            stepRow(step)
                        }
                        .foregroundStyle(KXColor.ink)
                    }
                    .onDelete { offsets in
                        workout.blocks[blockIndex].steps.remove(atOffsets: offsets)
                        if workout.blocks[blockIndex].steps.isEmpty { workout.blocks.remove(at: blockIndex) }
                    }
                    if block.repeats > 1 || block.steps.contains(where: { $0.kind == .work }) {
                        Button {
                            workout.blocks[blockIndex].steps.append(
                                WorkoutStep(kind: .recovery, length: .duration(seconds: 90)))
                        } label: {
                            Label("Add step to this block", systemImage: "plus")
                        }
                    }
                } header: {
                    HStack {
                        Text(blockTitle(block))
                        Spacer()
                        Button(role: .destructive) {
                            workout.blocks.remove(at: blockIndex)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete \(blockTitle(block))")
                    }
                }
            }

            Section {
                Menu {
                    Button("Warm-up") { add(.warmUp, .distance(meters: 2000)) }
                    Button("Steady run") { add(.steady, .distance(meters: 5000)) }
                    Button("Repeats (work + recovery)") {
                        workout.blocks.append(RunBlock(repeats: 4, steps: [
                            WorkoutStep(kind: .work, length: .duration(seconds: 180)),
                            WorkoutStep(kind: .recovery, length: .duration(seconds: 90))
                        ]))
                    }
                    Button("Cool-down") { add(.coolDown, .distance(meters: 2000)) }
                } label: {
                    Label("Add a block", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("builder.addBlock")
            }
        }
        .navigationTitle("Edit workout")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KXColor.accent)
        .sheet(item: $editing) { location in
            NavigationStack {
                StepEditorView(step: stepBinding(location), units: units, defaultPace: defaultPace)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = nil } }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private var totals: String {
        let estimate = workout.estimate(defaultPace: defaultPace)
        let format = DisplayFormat(units: units)
        return "≈ \(format.distance(estimate.distanceMeters)) · \(Units.formatMinutesSeconds(estimate.durationSeconds))"
    }

    private func blockTitle(_ block: RunBlock) -> String {
        if block.repeats > 1 { return "Repeat block" }
        switch block.steps.first?.kind {
        case .warmUp: return "Warm-up"
        case .coolDown: return "Cool-down"
        case .work: return "Effort"
        case .recovery: return "Recovery"
        default: return "Run"
        }
    }

    private func stepRow(_ step: WorkoutStep) -> some View {
        HStack(spacing: KXSpacing.md) {
            Circle().fill(color(for: step.kind)).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.kind.builderName).font(KXFont.bodyEmphasis)
                Text(CustomRunWorkout.describe(step.length, units: units))
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            Text(step.target?.formatted(units) ?? "No target")
                .font(KXFont.callout.monospacedDigit())
                .foregroundStyle(step.target == nil ? KXColor.inkTertiary : KXColor.ink)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func color(for kind: SegmentKind) -> Color {
        switch kind {
        case .work: return KXColor.run
        case .recovery: return KXColor.lift
        case .warmUp, .coolDown: return KXColor.other
        case .steady: return KXColor.accent
        }
    }

    private func add(_ kind: SegmentKind, _ length: SegmentLength) {
        let block = RunBlock(steps: [WorkoutStep(kind: kind, length: length)])
        if kind == .warmUp {
            workout.blocks.insert(block, at: 0)
        } else {
            workout.blocks.append(block)
        }
    }

    private func repeatsBinding(_ index: Int) -> Binding<Int> {
        Binding(get: { workout.blocks[index].repeats }, set: { workout.blocks[index].repeats = $0 })
    }

    private func stepBinding(_ location: StepLocation) -> Binding<WorkoutStep> {
        Binding(
            get: {
                guard workout.blocks.indices.contains(location.block),
                      workout.blocks[location.block].steps.indices.contains(location.step) else {
                    return WorkoutStep(kind: .steady, length: .distance(meters: 1000))
                }
                return workout.blocks[location.block].steps[location.step]
            },
            set: { newValue in
                guard workout.blocks.indices.contains(location.block),
                      workout.blocks[location.block].steps.indices.contains(location.step) else { return }
                workout.blocks[location.block].steps[location.step] = newValue
            }
        )
    }
}

/// Edits one step: type, distance or time, and the pace target.
struct StepEditorView: View {
    @Binding var step: WorkoutStep
    let units: UnitSystem
    let defaultPace: Pace

    private enum LengthMode: String, CaseIterable { case distance = "Distance", time = "Time" }
    private enum TargetMode: String, CaseIterable { case none = "None", single = "Pace", range = "Range" }

    var body: some View {
        Form {
            Section("Step") {
                Picker("Type", selection: $step.kind) {
                    ForEach([SegmentKind.warmUp, .steady, .work, .recovery, .coolDown], id: \.self) { kind in
                        Text(kind.builderName).tag(kind)
                    }
                }
            }

            Section("Length") {
                Picker("Measure by", selection: lengthMode) {
                    ForEach(LengthMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch step.length {
                case .distance:
                    DistanceField(meters: metersBinding, units: units)
                case .duration:
                    DurationPicker(seconds: secondsBinding)
                }
            }

            Section {
                Picker("Pace target", selection: targetMode) {
                    ForEach(TargetMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("step.targetMode")
                switch step.target {
                case .single(let pace):
                    PacePicker(label: "Target pace", pace: Binding(get: { pace }, set: { step.target = .single($0) }), units: units)
                case .range(let range):
                    PacePicker(label: "Fastest", pace: Binding(get: { range.fastest }, set: {
                        step.target = .range(PaceRange(fastest: $0, slowest: max($0, range.slowest)))
                    }), units: units)
                    PacePicker(label: "Slowest", pace: Binding(get: { range.slowest }, set: {
                        step.target = .range(PaceRange(fastest: min($0, range.fastest), slowest: $0))
                    }), units: units)
                case nil:
                    EmptyView()
                }
            } header: {
                Text("Pace")
            } footer: {
                Text(step.target == nil
                     ? "No target: you'll hear splits but no pace cues in this step."
                     : "Voice cues tell you to speed up or ease off when you drift outside the target (plus your tolerance from Settings → Audio coaching).")
            }
        }
        .navigationTitle(step.kind.builderName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lengthMode: Binding<LengthMode> {
        Binding(
            get: { if case .distance = step.length { return .distance } else { return .time } },
            set: { mode in
                // Convert using the step's pace so the step stays about the same size.
                let pace = step.target?.middle ?? defaultPace
                switch (mode, step.length) {
                case (.time, .distance(let meters)):
                    step.length = .duration(seconds: max(30, (meters / 1000 * pace.secondsPerKm / 30).rounded() * 30))
                case (.distance, .duration(let seconds)):
                    step.length = .distance(meters: max(100, (seconds / pace.secondsPerKm * 1000 / 100).rounded() * 100))
                default: break
                }
            }
        )
    }

    private var targetMode: Binding<TargetMode> {
        Binding(
            get: {
                switch step.target {
                case .none: return .none
                case .single: return .single
                case .range: return .range
                }
            },
            set: { mode in
                let middle = step.target?.middle ?? Pace(secondsPerKm: (defaultPace.secondsPerKm / 5).rounded() * 5)
                switch mode {
                case .none: step.target = nil
                case .single: step.target = .single(middle)
                case .range:
                    step.target = .range(PaceRange(fastest: Pace(secondsPerKm: middle.secondsPerKm - 5),
                                                   slowest: Pace(secondsPerKm: middle.secondsPerKm + 5)))
                }
            }
        )
    }

    private var metersBinding: Binding<Double> {
        Binding(get: { if case .distance(let m) = step.length { return m } else { return 1000 } },
                set: { step.length = .distance(meters: $0) })
    }

    private var secondsBinding: Binding<Double> {
        Binding(get: { if case .duration(let s) = step.length { return s } else { return 600 } },
                set: { step.length = .duration(seconds: $0) })
    }
}

/// Minutes : seconds wheels for a pace in the runner's units (5-second steps).
struct PacePicker: View {
    let label: String
    @Binding var pace: Pace
    let units: UnitSystem

    private var perUnit: Double { units == .metric ? 1 : Units.metersPerMile / 1000 }
    private var totalSeconds: Int { Int((pace.secondsPerKm * perUnit / 5).rounded() * 5) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack {
                Text(label)
                Spacer()
                Text(Units.formatPace(pace, units: units) + Units.paceUnitLabel(units))
                    .font(KXFont.bodyEmphasis.monospacedDigit())
                    .foregroundStyle(KXColor.accent)
            }
            HStack(spacing: 0) {
                Picker("Minutes", selection: Binding(get: { totalSeconds / 60 }, set: { set(minutes: $0, seconds: totalSeconds % 60) })) {
                    ForEach(2...15, id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Seconds", selection: Binding(get: { totalSeconds % 60 }, set: { set(minutes: totalSeconds / 60, seconds: $0) })) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d s", $0)).tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
        }
        .accessibilityElement(children: .contain)
    }

    private func set(minutes: Int, seconds: Int) {
        pace = Pace(secondsPerKm: Double(minutes * 60 + seconds) / perUnit)
    }
}

/// Hours/minutes/seconds wheels for a timed step.
struct DurationPicker: View {
    @Binding var seconds: Double

    private var total: Int { Int(seconds.rounded()) }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Minutes", selection: Binding(get: { total / 60 }, set: { seconds = Double($0 * 60 + total % 60) })) {
                ForEach(0...180, id: \.self) { Text("\($0) min").tag($0) }
            }
            Picker("Seconds", selection: Binding(get: { (total % 60) / 5 * 5 }, set: { seconds = Double((total / 60) * 60 + $0) })) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d s", $0)).tag($0) }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 120)
        .onChange(of: total) { _, newValue in if newValue < 5 { seconds = 5 } }
    }
}

/// A distance typed in km or miles (stored in metres).
struct DistanceField: View {
    @Binding var meters: Double
    let units: UnitSystem
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("Distance", text: $text)
                .keyboardType(.decimalPad)
                .focused($focused)
                .font(KXFont.bodyEmphasis.monospacedDigit())
                .onChange(of: text) { _, newValue in
                    let value = Double(newValue.replacingOccurrences(of: ",", with: ".")) ?? 0
                    if value > 0 { meters = units == .metric ? value * 1000 : value * Units.metersPerMile }
                }
            Text(Units.distanceUnitLabel(units)).foregroundStyle(KXColor.inkSecondary)
        }
        .onAppear {
            let value = Units.distance(meters: meters, in: units)
            text = value == value.rounded() ? String(Int(value)) : String((value * 100).rounded() / 100)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }
}

extension SegmentKind {
    var builderName: String {
        switch self {
        case .warmUp: return "Warm-up"
        case .work: return "Effort"
        case .recovery: return "Recovery"
        case .coolDown: return "Cool-down"
        case .steady: return "Steady"
        }
    }
}
