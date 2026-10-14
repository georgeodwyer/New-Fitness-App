import SwiftUI
import SwiftData
import TrainingEngine

/// Choose a run type, adjust the workout, then start, optionally saving it as a template.
/// If a planned run is due today, asks whether this is it.
struct RunSetupView: View {
    let initial: RunTemplateModel?

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]

    @State private var workout: CustomRunWorkout
    @State private var template: RunTemplateModel?
    @State private var askAboutPlan = false
    @State private var savedMessage: String?
    @State private var showHealthNotice = false
    @AppStorage(HealthNotice.key) private var healthNoticeAccepted = false

    init(initial: RunTemplateModel?) {
        self.initial = initial
        _workout = State(initialValue: initial?.workout ?? CustomRunWorkout.starter(for: .free, zones: nil))
        _template = State(initialValue: initial)
    }

    private var profile: AthleteProfile? { profiles.first?.profile }
    private var units: UnitSystem { profile?.units ?? UnitPreference.stored }
    private var zones: PaceZones? { profile.map(PaceZones.init(profile:)) }
    private var defaultPace: Pace { zones?.typicalPace(for: .easy) ?? Pace(secondsPerKm: 360) }

    /// Planned runs still to do today.
    private var plannedToday: [PlannedSessionModel] {
        sessions.filter {
            !$0.isSoftDeleted && Calendar.kinetix.isDateInToday($0.date) && $0.kind.discipline == .run
                && ($0.status == .planned || $0.status == .swapped) && ($0.plan?.isActive ?? true)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                typePicker
                workoutCard
                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .font(KXFont.callout).foregroundStyle(KXColor.ink)
                        .symbolRenderingMode(.multicolor)
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle(template == nil ? "New run" : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: KXSpacing.sm) {
                Button {
                    if !healthNoticeAccepted { showHealthNotice = true } else { proceed() }
                } label: {
                    Label("Start run", systemImage: "play.fill")
                }
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("record.startRun")
                if workout.type != .free || !workout.blocks.isEmpty {
                    Button(template == nil ? "Save as template" : "Save changes to template") { saveTemplate() }
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                        .accessibilityIdentifier("record.saveTemplate")
                }
            }
            .padding(KXSpacing.screenMargin)
            .background(KXColor.background)
        }
        .sheet(isPresented: $showHealthNotice) {
            HealthNoticeSheet {
                healthNoticeAccepted = true
                showHealthNotice = false
                // Let the sheet close before the run screen opens.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proceed() }
            }
        }
        .confirmationDialog(planQuestion, isPresented: $askAboutPlan, titleVisibility: .visible) {
            if let planned = plannedToday.first {
                Button("Yes, count it as my \(planned.title.lowercased())") { start(linking: planned) }
                Button("No, it's an extra run") { start(linking: nil) }
                Button("Do the planned \(planned.title.lowercased()) instead") {
                    router.activeSession = ActiveSession(id: planned.id, kind: planned.kind, title: planned.title)
                }
            }
        } message: {
            if let planned = plannedToday.first {
                Text("Your plan has \(planned.title.lowercased()) (\(planned.summary)) today. If this run replaces it, it's ticked off; if not, both count towards your training load.")
            }
        }
    }

    private func proceed() {
        if plannedToday.isEmpty { start(linking: nil) } else { askAboutPlan = true }
    }

    private var planQuestion: String {
        plannedToday.first.map { "You have \($0.title.lowercased()) planned today. Is this it?" } ?? ""
    }

    // MARK: Sections

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Run type")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: KXSpacing.sm)], spacing: KXSpacing.sm) {
                ForEach(RecordRunType.allCases, id: \.self) { type in
                    Button {
                        select(type)
                    } label: {
                        HStack(spacing: KXSpacing.sm) {
                            Image(systemName: type.symbol).frame(width: 22)
                            Text(type.displayName).font(KXFont.captionEmphasis).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(workout.type == type ? KXColor.onAccent : KXColor.ink)
                        .padding(.horizontal, KXSpacing.md)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(workout.type == type ? KXColor.accent : KXColor.surface,
                                    in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(workout.type == type ? .isSelected : [])
                    .accessibilityIdentifier("record.type.\(type.rawValue)")
                }
            }
            Text(workout.type.detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }

    private var workoutCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Workout")
            TextField("Name", text: $workout.name)
                .font(KXFont.headline)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("record.name")
            if workout.blocks.isEmpty {
                Text(workout.type == .free
                     ? "Just press start. You'll hear your splits; there are no pace targets."
                     : "No steps yet. Add some with Edit workout.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            } else {
                Text(workout.summary(units: units)).font(KXFont.callout).foregroundStyle(KXColor.ink)
                let estimate = workout.estimate(defaultPace: defaultPace)
                HStack(spacing: KXSpacing.xl) {
                    KXMetric(label: "About", value: DisplayFormat(units: units).distance(estimate.distanceMeters), size: .small)
                    KXMetric(label: "Time", value: Units.formatMinutesSeconds(estimate.durationSeconds), size: .small)
                }
            }
            NavigationLink {
                WorkoutBuilderView(workout: $workout, units: units, defaultPace: defaultPace)
            } label: {
                Label(workout.blocks.isEmpty ? "Add steps and pace targets" : "Edit workout", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.kx(.secondary, fullWidth: true))
            .accessibilityIdentifier("record.editWorkout")
        }
        .kxCard()
    }

    // MARK: Actions

    private func select(_ type: RecordRunType) {
        guard type != workout.type || template != nil else { return }
        workout = CustomRunWorkout.starter(for: type, zones: zones)
        template = nil
        savedMessage = nil
    }

    private func saveTemplate() {
        if workout.name.trimmingCharacters(in: .whitespaces).isEmpty { workout.name = workout.type.displayName }
        if let template {
            template.workout = workout
            template.touch()
            savedMessage = "Template updated"
        } else {
            let model = RunTemplateModel(workout: workout)
            context.insert(model)
            template = model
            workout.id = model.id
            savedMessage = "Saved to My run workouts"
        }
        try? context.save()
        SyncService.shared.requestSync()
    }

    private func start(linking planned: PlannedSessionModel?) {
        if workout.name.trimmingCharacters(in: .whitespaces).isEmpty { workout.name = workout.type.displayName }
        if let template {
            template.lastUsedAt = .now
            template.touch()
            try? context.save()
        }
        router.activeSession = ActiveSession(id: UUID(), kind: .run(workout.type.sessionType ?? .easy), title: workout.name,
                                             custom: workout, linkedPlannedId: planned?.id)
    }
}

extension RecordRunType {
    var symbol: String {
        switch self {
        case .free: return "figure.run"
        case .easy: return "leaf"
        case .recovery: return "bed.double"
        case .long: return "road.lanes"
        case .tempo: return "speedometer"
        case .intervals: return "repeat"
        case .progression: return "chart.line.uptrend.xyaxis"
        case .fartlek: return "waveform.path"
        }
    }
}
