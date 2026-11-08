import SwiftUI
import SwiftData
import TrainingEngine

/// Build or edit a functional workout: name, format (rounds, intervals, EMOM, AMRAP) and the
/// stations in order. Runs can have a pace (set, or one of your training paces) and a treadmill.
struct FunctionalEditorView: View {
    let template: FunctionalTemplateModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]

    @State private var workout: FunctionalWorkout
    @State private var pickingExercise = false
    @State private var confirmDelete = false

    init(template: FunctionalTemplateModel?, initial: FunctionalWorkout? = nil) {
        self.template = template
        _workout = State(initialValue: template?.workout ?? initial ?? FunctionalWorkout(name: "", format: .rounds(3)))
    }

    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }
    private var zones: PaceZones? { profiles.first.map { PaceZones(profile: $0.profile) } }

    private enum Mode: String, CaseIterable { case rounds = "Rounds", intervals = "Intervals", emom = "EMOM", amrap = "AMRAP" }

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Hyrox engine", text: $workout.name)
                    .accessibilityIdentifier("functional.name")
            }
            formatSection
            stationsSection
            Section {
                Button {
                    save()
                    start()
                } label: {
                    Label("Save and start", systemImage: "play.fill")
                }
                .disabled(workout.stations.isEmpty)
                if template != nil {
                    Button("Delete workout", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(template == nil ? "New functional workout" : "Edit workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("functional.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(workout.stations.isEmpty)
                .accessibilityIdentifier("functional.save")
            }
        }
        .sheet(isPresented: $pickingExercise) {
            ExercisePickerView(excluding: []) { exercise in
                workout.stations.append(FunctionalStation(kind: .exercise, exerciseId: exercise.id, name: exercise.name, target: .reps(10)))
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                template?.softDelete()
                try? context.save()
                SyncService.shared.requestSync()
                dismiss()
            }
        }
    }

    // MARK: Format

    private var mode: Binding<Mode> {
        Binding(
            get: {
                switch workout.format {
                case .rounds: return .rounds
                case .intervals: return .intervals
                case .emom: return .emom
                case .amrap: return .amrap
                }
            },
            set: { mode in
                switch mode {
                case .rounds: workout.format = .rounds(3)
                case .intervals: workout.format = .intervals(work: 40, rest: 20, rounds: 3)
                case .emom: workout.format = .emom(every: 60, rounds: max(10, workout.stations.count * 4))
                case .amrap: workout.format = .amrap(cap: 20 * 60)
                }
            }
        )
    }

    private var formatSection: some View {
        Section {
            Picker("Format", selection: mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch workout.format {
            case .rounds(let rounds):
                Stepper("\(rounds) round\(rounds == 1 ? "" : "s")", value: Binding(get: { rounds }, set: { workout.format = .rounds($0) }), in: 1...50)
            case .intervals(let work, let rest, let rounds):
                Stepper("Work \(Int(work)) s", value: Binding(get: { work }, set: { workout.format = .intervals(work: $0, rest: rest, rounds: rounds) }),
                        in: 5...600, step: 5)
                Stepper("Rest \(Int(rest)) s", value: Binding(get: { rest }, set: { workout.format = .intervals(work: work, rest: $0, rounds: rounds) }),
                        in: 0...600, step: 5)
                Stepper("\(rounds) round\(rounds == 1 ? "" : "s")", value: Binding(get: { rounds }, set: {
                    workout.format = .intervals(work: work, rest: rest, rounds: $0)
                }), in: 1...50)
            case .emom(let every, let rounds):
                Stepper(every == 60 ? "Every minute" : "Every \(Units.formatMinutesSeconds(every))",
                        value: Binding(get: { every }, set: { workout.format = .emom(every: $0, rounds: rounds) }), in: 15...600, step: 15)
                Stepper("\(rounds) interval\(rounds == 1 ? "" : "s") · \(Units.formatMinutesSeconds(every * Double(rounds)))",
                        value: Binding(get: { rounds }, set: { workout.format = .emom(every: every, rounds: $0) }), in: 1...120)
            case .amrap(let cap):
                Stepper("\(Int(cap / 60)) min", value: Binding(get: { cap / 60 }, set: { workout.format = .amrap(cap: $0 * 60) }), in: 1...120)
            }
        } header: {
            Text("Format")
        } footer: {
            Text(formatHelp)
        }
    }

    private var formatHelp: String {
        switch workout.format {
        case .rounds: return "Every station in order, round after round, as fast as you can. Tap Next as you finish each one; timed stations and rests move on by themselves."
        case .intervals: return "Each station gets the work time, then the rest; the clock moves you on."
        case .emom: return "A new station starts every interval, in turn. Finish early and you rest until the next one."
        case .amrap: return "As many rounds of the stations as you can before the time's up."
        }
    }

    // MARK: Stations

    private var stationsSection: some View {
        Section {
            if workout.stations.isEmpty {
                Text("Add your first station below.").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            ForEach($workout.stations) { $station in
                NavigationLink {
                    StationEditorView(station: $station, units: units, zones: zones)
                } label: {
                    stationRow(station)
                }
                .contextMenu {
                    Button {
                        if let index = workout.stations.firstIndex(where: { $0.id == station.id }) {
                            var copy = station
                            copy.id = UUID()
                            workout.stations.insert(copy, at: index + 1)
                        }
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                }
            }
            .onDelete { workout.stations.remove(atOffsets: $0) }
            .onMove { workout.stations.move(fromOffsets: $0, toOffset: $1) }
            addMenu
        } header: {
            HStack {
                Text("Stations")
                Spacer()
                if workout.stations.count > 1 { EditButton().font(KXFont.captionEmphasis) }
            }
        } footer: {
            Text("Tap a station to set its distance, time, reps, weight or run pace. Swipe to delete; Edit to reorder.")
        }
    }

    private var addMenu: some View {
        Menu {
            Section("Cardio") {
                ForEach([FunctionalStation.Kind.run, .ski, .row, .bike], id: \.self) { kind in
                    Button(kind.displayName) { add(kind) }
                }
            }
            Section("Hyrox stations") {
                ForEach([FunctionalStation.Kind.sledPush, .sledPull, .burpeeBroadJumps, .farmersCarry, .sandbagLunges, .wallBalls], id: \.self) { kind in
                    Button(kind.displayName) { add(kind) }
                }
            }
            Button("Gym exercise…") { pickingExercise = true }
            Button("Rest") { add(.rest) }
        } label: {
            Label("Add station", systemImage: "plus.circle.fill")
                .font(KXFont.bodyEmphasis)
        }
        .accessibilityIdentifier("functional.addStation")
    }

    private func add(_ kind: FunctionalStation.Kind) {
        var station = FunctionalStation(kind: kind)
        // Hyrox weights for your division, as a starting point.
        if [.sledPush, .sledPull, .farmersCarry, .sandbagLunges, .wallBalls].contains(kind) {
            let division = profiles.first?.profile.hyroxDivision ?? .openMen
            station.weightKg = HyroxSimulation.workout(division: division).stations.first { $0.kind == kind }?.weightKg
        }
        if kind == .run, case .intervals = workout.format { station.target = .seconds(60) }
        workout.stations.append(station)
    }

    private func stationRow(_ station: FunctionalStation) -> some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: Self.symbol(for: station.kind))
                .foregroundStyle(station.kind == .rest ? KXColor.inkTertiary : KXColor.functional)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(station.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                let info = details(station)
                if !info.isEmpty {
                    Text(info).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func details(_ station: FunctionalStation) -> String {
        var parts: [String] = []
        if let kg = station.weightKg, kg > 0 { parts.append(DisplayFormat(units: units).weight(kg)) }
        if station.kind == .run {
            if station.treadmill { parts.append("treadmill") }
            switch station.pace {
            case .fixed(let target)?: parts.append(target.formatted(units))
            case .zone(let zone)?: parts.append("\(zone.displayName) pace")
            case nil: parts.append("by feel")
            }
        }
        return parts.joined(separator: " · ")
    }

    static func symbol(for kind: FunctionalStation.Kind) -> String {
        switch kind {
        case .run: return "figure.run"
        case .ski: return "figure.skiing.crosscountry"
        case .row: return "figure.rower"
        case .bike: return "figure.indoor.cycle"
        case .sledPush, .sledPull: return "figure.strengthtraining.functional"
        case .burpeeBroadJumps: return "figure.jumprope"
        case .farmersCarry: return "figure.walk"
        case .sandbagLunges: return "figure.step.training"
        case .wallBalls: return "basketball.fill"
        case .exercise: return "dumbbell.fill"
        case .rest: return "pause.circle"
        }
    }

    // MARK: Saving

    private func save() {
        let trimmed = workout.name.trimmingCharacters(in: .whitespaces)
        workout.name = trimmed.isEmpty ? "Functional workout" : trimmed
        if let template {
            template.workout = workout
            template.touch()
        } else {
            context.insert(FunctionalTemplateModel(workout: workout))
        }
        try? context.save()
        SyncService.shared.requestSync()
    }

    private func start() {
        let session = ActiveSession(id: UUID(), kind: .crossTraining, title: workout.name, functional: workout,
                                    functionalTemplateId: workout.id)
        let router = router
        // Close the builder first, then open the workout over the app.
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { router.start(session) }
    }
}

// MARK: - One station

struct StationEditorView: View {
    @Binding var station: FunctionalStation
    let units: UnitSystem
    let zones: PaceZones?

    private enum Measure: String, CaseIterable { case distance = "Distance", time = "Time", reps = "Reps", calories = "Calories" }
    private enum PaceMode: String, CaseIterable { case feel = "By feel", set = "Set pace", training = "Training pace" }

    private var format: DisplayFormat { DisplayFormat(units: units) }

    private var measures: [Measure] {
        switch station.kind {
        case .run, .farmersCarry, .sandbagLunges, .sledPush, .sledPull, .burpeeBroadJumps: return [.distance, .time]
        case .ski, .row, .bike: return [.distance, .time, .calories]
        case .rest: return [.time]
        case .wallBalls, .exercise: return [.reps, .time]
        }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField(station.kind.displayName, text: $station.name)
            }
            targetSection
            if hasWeight {
                weightSection
            }
            if station.kind == .run {
                runSection
            }
        }
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Target

    private var measure: Binding<Measure> {
        Binding(
            get: {
                switch station.target {
                case .meters: return .distance
                case .seconds: return .time
                case .reps: return .reps
                case .calories: return .calories
                }
            },
            set: { measure in
                switch measure {
                case .distance: station.target = station.kind.defaultTarget.isDistance ? station.kind.defaultTarget : .meters(500)
                case .time: station.target = .seconds(60)
                case .reps: station.target = .reps(10)
                case .calories: station.target = .calories(15)
                }
            }
        )
    }

    private var targetSection: some View {
        Section("How much") {
            if measures.count > 1 {
                Picker("Measure", selection: measure) {
                    ForEach(measures, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch station.target {
            case .meters(let meters):
                Stepper(format.shortDistance(meters), value: Binding(get: { meters }, set: { station.target = .meters($0) }),
                        in: 5...42_195, step: meters < 100 ? 5 : (meters < 1000 ? 25 : 100))
            case .seconds(let seconds):
                DurationPicker(seconds: Binding(get: { seconds }, set: { station.target = .seconds($0) }))
            case .reps(let reps):
                Stepper("\(reps) reps", value: Binding(get: { reps }, set: { station.target = .reps($0) }), in: 1...500)
            case .calories(let calories):
                Stepper("\(calories) cal", value: Binding(get: { calories }, set: { station.target = .calories($0) }), in: 1...500)
            }
        }
    }

    // MARK: Weight

    private var hasWeight: Bool {
        ![.run, .ski, .row, .bike, .rest, .burpeeBroadJumps].contains(station.kind)
    }

    private var weightSection: some View {
        Section("Weight") {
            Toggle("Weighted", isOn: Binding(get: { station.weightKg != nil }, set: { station.weightKg = $0 ? 20 : nil }))
            if let kg = station.weightKg {
                Stepper(format.weight(kg), value: Binding(get: { kg }, set: { station.weightKg = $0 }),
                        in: 0.5...500, step: kg < 20 ? 0.5 : 2.5)
            }
        }
    }

    // MARK: Run

    private var paceMode: Binding<PaceMode> {
        Binding(
            get: {
                switch station.pace {
                case nil: return .feel
                case .fixed?: return .set
                case .zone?: return .training
                }
            },
            set: { mode in
                switch mode {
                case .feel: station.pace = nil
                case .set:
                    let start = zones?.range(for: .threshold).fastest.secondsPerKm ?? 300
                    station.pace = .fixed(.single(Pace(secondsPerKm: (start / 5).rounded() * 5)))
                case .training: station.pace = .zone(.threshold)
                }
            }
        )
    }

    private static let trainingZones: [PaceZone] = [.easy, .steady, .marathon, .halfMarathon, .threshold, .tenK, .fiveK, .interval, .repetition]

    private var runSection: some View {
        Section {
            Toggle("On a treadmill", isOn: $station.treadmill)
            Picker("Pace", selection: paceMode) {
                ForEach(PaceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch station.pace {
            case .fixed(let target)?:
                PacePicker(label: "Target pace", pace: Binding(get: { target.middle }, set: { station.pace = .fixed(.single($0)) }), units: units)
            case .zone(let zone)?:
                Picker("Training pace", selection: Binding(get: { zone }, set: { station.pace = .zone($0) })) {
                    ForEach(Self.trainingZones, id: \.self) { zone in
                        Text(zoneLabel(zone)).tag(zone)
                    }
                }
            case nil:
                EmptyView()
            }
            if let speed = treadmillSpeed {
                Label("Treadmill speed \(speed)", systemImage: "figure.run.treadmill")
                    .font(KXFont.callout)
            }
        } header: {
            Text("Run")
        } footer: {
            Text(station.treadmill
                 ? "Treadmill runs are timed (no GPS); Kinetix shows the speed to set for the pace."
                 : "Outside, Kinetix shows your pace against the target and tells you to speed up or ease off. Training paces follow your fitness as it changes.")
        }
    }

    private func zoneLabel(_ zone: PaceZone) -> String {
        guard let zones else { return zone.displayName }
        let range = zones.range(for: zone)
        return "\(zone.displayName) · \(range.fastest == range.slowest ? format.pace(range.fastest) : format.paceRange(range))"
    }

    private var treadmillSpeed: String? {
        guard station.treadmill, let pace = station.pace else { return nil }
        let range = pace.range(zones: zones ?? PaceZones(race: RaceResult(distanceMeters: 5000, timeSeconds: 1500)))
        let middle = Pace(secondsPerKm: (range.fastest.secondsPerKm + range.slowest.secondsPerKm) / 2)
        return units == .imperial ? String(format: "%.1f mph", middle.kilometresPerHour / 1.609344)
                                  : String(format: "%.1f km/h", middle.kilometresPerHour)
    }
}

private extension FunctionalTarget {
    var isDistance: Bool { if case .meters = self { return true } else { return false } }
}
