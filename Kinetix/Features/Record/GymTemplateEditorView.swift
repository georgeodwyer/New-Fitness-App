import SwiftUI
import SwiftData
import TrainingEngine

/// Build or edit a saved gym workout: exercises in order, each with sets, rep range and rest.
struct GymTemplateEditorView: View {
    let template: GymTemplateModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var items: [GymTemplateItem]
    @State private var showPicker = false
    @State private var startRequest: GymStartRequest?

    init(template: GymTemplateModel?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _items = State(initialValue: template?.items ?? [])
    }

    private var trimmedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Gym workout" : trimmed
    }

    var body: some View {
        List {
            Section {
                TextField("Name, e.g. Push day", text: $name)
                    .font(KXFont.headline)
                    .accessibilityIdentifier("gym.templateName")
            } footer: {
                if !items.isEmpty { Text(GymTemplate.summary(items)) }
            }

            Section("Exercises") {
                if items.isEmpty {
                    Text("No exercises yet.")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                ForEach($items) { $item in
                    ItemEditor(item: $item)
                }
                .onDelete { items.remove(atOffsets: $0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    showPicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .accessibilityIdentifier("gym.templateAddExercise")
            }
        }
        .scrollContentBackground(.hidden)
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle(template == nil ? "New workout" : "Edit workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty { EditButton() }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: KXSpacing.sm) {
                Button {
                    startRequest = GymStartRequest(title: trimmedName, items: items, templateId: template?.id)
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .disabled(items.isEmpty)
                .accessibilityIdentifier("gym.templateStart")
                Button(template == nil ? "Save workout" : "Save changes") { save() }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
                    .disabled(items.isEmpty)
                    .accessibilityIdentifier("gym.templateSave")
            }
            .padding(KXSpacing.screenMargin)
            .background(KXColor.background)
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView(excluding: Set(items.map(\.exerciseId))) { exercise in
                items.append(.starter(for: exercise))
            }
        }
        .gymStartFlow($startRequest)
    }

    private func save() {
        if let template {
            template.name = trimmedName
            template.items = items
            template.touch()
        } else {
            context.insert(GymTemplateModel(name: trimmedName, items: items))
        }
        try? context.save()
        SyncService.shared.requestSync()
        dismiss()
    }
}

/// One exercise: sets, rep range and rest.
private struct ItemEditor: View {
    @Binding var item: GymTemplateItem

    private static let restChoices = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    private var restOptions: [Int] {
        Self.restChoices.contains(item.restSeconds) ? Self.restChoices : (Self.restChoices + [item.restSeconds]).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Text(item.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Spacer()
                Text(item.setsAndReps).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Stepper("Sets: \(item.sets)", value: $item.sets, in: 1...10)
            Stepper("Reps from: \(item.repsLow)", value: Binding(
                get: { item.repsLow },
                set: { item.repsLow = $0; item.repsHigh = max(item.repsHigh, $0) }
            ), in: 1...50)
            Stepper("Reps up to: \(item.repsHigh)", value: Binding(
                get: { item.repsHigh },
                set: { item.repsHigh = $0; item.repsLow = min(item.repsLow, $0) }
            ), in: 1...50)
            Picker("Rest", selection: $item.restSeconds) {
                ForEach(restOptions, id: \.self) { seconds in
                    Text(Units.formatMinutesSeconds(Double(seconds))).tag(seconds)
                }
            }
        }
        .font(KXFont.callout)
        .padding(.vertical, KXSpacing.xxs)
    }
}

// MARK: - Exercise picker

/// Search the library by name, filter by muscle group and equipment, or add your own.
struct ExercisePickerView: View {
    let excluding: Set<String>
    let onPick: (ExerciseDefinition) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<CustomExerciseModel> { $0.deletedAt == nil }, sort: \CustomExerciseModel.name)
    private var custom: [CustomExerciseModel]
    @State private var query = ""
    @State private var muscle: MuscleGroup?
    @State private var loading: ExerciseLoading?
    @State private var showCreate = false

    private var results: [ExerciseDefinition] {
        ExerciseSearch.filter(PlanService.templates.exercises + custom.map(\.definition), query: query, muscle: muscle, loading: loading)
    }

    private var customIds: Set<String> { Set(custom.map(\.exerciseId)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterRow(MuscleGroup.allCases, selection: $muscle, label: \.displayName, prefix: "muscle")
                    filterRow(ExerciseLoading.allCases, selection: $loading, label: \.displayName, prefix: "equipment")
                }
                .listRowInsets(EdgeInsets(top: KXSpacing.xs, leading: 0, bottom: KXSpacing.xs, trailing: 0))
                .listRowBackground(Color.clear)

                Section {
                    ForEach(results, id: \.id) { exercise in
                        let added = excluding.contains(exercise.id)
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name).font(KXFont.body).foregroundStyle(KXColor.ink)
                                    Text("\(exercise.muscleGroup.displayName) · \(exercise.loading.displayName)")
                                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                }
                                Spacer()
                                if added {
                                    Text("Added").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                                } else if customIds.contains(exercise.id) {
                                    KXChip(text: "Yours", variant: .outlined)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(added)
                        .accessibilityIdentifier("gym.exercise.\(exercise.id)")
                    }
                    if results.isEmpty {
                        Text("No exercises match. Try another search, or add it as your own.")
                            .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    }
                    Button {
                        showCreate = true
                    } label: {
                        Label(query.isEmpty ? "Add your own exercise" : "Add \u{201C}\(query)\u{201D} as your own", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("gym.createExercise")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showCreate) {
                CreateExerciseView(initialName: query, initialMuscle: muscle, initialLoading: loading) { model in
                    onPick(model.definition)
                    dismiss()
                }
            }
        }
    }

    private func filterRow<T: Hashable>(_ options: [T], selection: Binding<T?>, label: KeyPath<T, String>, prefix: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.xs) {
                ForEach(options, id: \.self) { option in
                    let selected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = selected ? nil : option
                    } label: {
                        Text(option[keyPath: label])
                            .font(KXFont.captionEmphasis)
                            .foregroundStyle(selected ? KXColor.onAccent : KXColor.ink)
                            .padding(.horizontal, KXSpacing.md)
                            .frame(minHeight: 36)
                            .background(selected ? KXColor.accent : KXColor.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, KXSpacing.screenMargin)
        }
    }
}

/// Name, muscle group and equipment for an exercise that isn't in the library.
private struct CreateExerciseView: View {
    let onCreate: (CustomExerciseModel) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var muscle: MuscleGroup
    @State private var loading: ExerciseLoading

    init(initialName: String, initialMuscle: MuscleGroup?, initialLoading: ExerciseLoading?, onCreate: @escaping (CustomExerciseModel) -> Void) {
        _name = State(initialValue: initialName)
        _muscle = State(initialValue: initialMuscle ?? .chest)
        _loading = State(initialValue: initialLoading ?? .dumbbell)
        self.onCreate = onCreate
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                    .accessibilityIdentifier("gym.newExerciseName")
                Picker("Muscle group", selection: $muscle) {
                    ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Equipment", selection: $loading) {
                    ForEach(ExerciseLoading.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            .navigationTitle("Your exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let model = CustomExerciseModel(name: trimmed, muscle: muscle, loading: loading)
                        context.insert(model)
                        try? context.save()
                        SyncService.shared.requestSync()
                        dismiss()
                        onCreate(model)
                    }
                    .disabled(trimmed.isEmpty)
                    .accessibilityIdentifier("gym.saveNewExercise")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
