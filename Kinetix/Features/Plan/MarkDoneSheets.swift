import SwiftData
import SwiftUI
import TrainingEngine

/// Sessions done without Kinetix (forgot the app, a treadmill…) can be marked done from today
/// back to a week ago.
extension PlannedSessionModel {
    func canMarkDone(now: Date = .now) -> Bool {
        guard status == .planned || status == .swapped,
              kind.discipline == .run || kind.discipline == .strength else { return false }
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) else { return false }
        return day <= today && day >= weekAgo
    }

    /// When it was done: the session's day, at the current time if that's today, else midday.
    func defaultDoneTime(duration: Double, now: Date = .now) -> Date {
        let calendar = Calendar.kinetix
        if calendar.isDate(date, inSameDayAs: now) { return now.addingTimeInterval(-duration) }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}

/// A planned run done without recording it: pre-filled from the plan, or from a run in
/// Apple Health that day.
struct MarkDoneRunSheet: View {
    let session: PlannedSessionModel
    let units: UnitSystem
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var meters: Double
    @State private var seconds: Double
    @State private var effort: Double
    @State private var startedAt: Date
    @State private var heartRate: Double?
    @State private var usedWorkoutId: UUID?
    @State private var fieldsVersion = 0

    init(session: PlannedSessionModel, units: UnitSystem, onDone: @escaping () -> Void) {
        self.session = session
        self.units = units
        self.onDone = onDone
        let duration = max(session.plannedDurationMinutes, 5) * 60
        _meters = State(initialValue: session.estimatedDistanceMeters ?? 5000)
        _seconds = State(initialValue: duration)
        _effort = State(initialValue: session.plannedEffort)
        _startedAt = State(initialValue: session.defaultDoneTime(duration: duration))
    }

    /// Runs in Apple Health on the session's day.
    private var healthRuns: [ExternalWorkout] {
        let settings = IntegrationSettings.shared
        guard settings.healthEnabled else { return [] }
        return settings.externalWorkouts
            .filter { $0.kind == .run && Calendar.kinetix.isDate($0.start, inSameDayAs: session.date) }
            .sorted { $0.start < $1.start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    Text("Ran it without Kinetix, or on a treadmill? Check the details and save. It counts towards your plan and training load.")
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)

                    if !healthRuns.isEmpty {
                        VStack(alignment: .leading, spacing: KXSpacing.sm) {
                            KXOverline("From Apple Health")
                            ForEach(healthRuns) { workout in healthRow(workout) }
                        }
                        .kxCard()
                    }

                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        KXOverline("Distance")
                        DistanceField(meters: $meters, units: units).id(fieldsVersion)
                        KXOverline("Time")
                        DurationPicker(seconds: $seconds)
                        DatePicker("Started", selection: $startedAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                            .font(KXFont.body)
                    }
                    .kxCard()

                    KXStepper(label: "Effort", value: $effort, step: 1, range: 1...10, unit: "/10",
                              format: { String(Int($0)) })
                        .frame(maxWidth: .infinity)
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Mark as done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save run") { save() }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .disabled(seconds < 60)
                    .padding(KXSpacing.screenMargin)
                    .background(KXColor.background)
                    .accessibilityIdentifier("markDone.saveRun")
            }
        }
    }

    private func healthRow(_ workout: ExternalWorkout) -> some View {
        let used = usedWorkoutId == workout.id
        let details = [workout.start.formatted(date: .omitted, time: .shortened),
                       workout.distanceMeters.map { DisplayFormat(units: units).distance($0) },
                       Units.formatMinutesSeconds(workout.durationSeconds)]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(workout.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(details).font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            Button(used ? "Using" : "Use this workout") { use(workout) }
                .buttonStyle(.kx(used ? .outlined : .primary))
                .disabled(used)
        }
    }

    private func use(_ workout: ExternalWorkout) {
        if let distance = workout.distanceMeters, distance > 0 { meters = distance }
        seconds = max(workout.durationSeconds.rounded(), 60)
        startedAt = workout.start
        heartRate = workout.averageHeartRate
        let maxHeartRate = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
            .filter { $0.isFinished && !$0.isSoftDeleted }.compactMap(\.maxHeartRate).max()
        effort = workout.estimatedEffort(maxHeartRate: maxHeartRate)
        usedWorkoutId = workout.id
        fieldsVersion += 1 // refresh the typed distance
    }

    private func save() {
        RunService.logManual(for: session, startedAt: startedAt, durationSeconds: seconds, distanceMeters: meters,
                             effort: effort, averageHeartRate: heartRate, in: context)
        onDone()
        dismiss()
    }
}

/// A planned gym session done without tracking it: did they do every set as planned?
/// Yes progresses weights as usual; not all of it holds them.
struct MarkDoneGymSheet: View {
    let session: PlannedSessionModel
    let units: UnitSystem
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var allSetsDone: Bool?
    @State private var seconds: Double
    @State private var effort: Double
    @State private var startedAt: Date

    init(session: PlannedSessionModel, units: UnitSystem, onDone: @escaping () -> Void) {
        self.session = session
        self.units = units
        self.onDone = onDone
        let duration = max(session.plannedDurationMinutes, 5) * 60
        _seconds = State(initialValue: duration)
        _effort = State(initialValue: session.plannedEffort)
        _startedAt = State(initialValue: session.defaultDoneTime(duration: duration))
    }

    private var exercises: [StrengthExercisePrescriptionLike] {
        (session.strengthPrescription?.exercises ?? []).map {
            StrengthExercisePrescriptionLike(name: $0.name, detail: "\($0.sets) × \($0.repRange.lower)–\($0.repRange.upper)")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    if !exercises.isEmpty {
                        VStack(alignment: .leading, spacing: KXSpacing.xs) {
                            KXOverline("The session")
                            ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                                HStack {
                                    Text(exercise.name).font(KXFont.callout).foregroundStyle(KXColor.ink)
                                    Spacer()
                                    Text(exercise.detail).font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                                }
                            }
                        }
                        .kxCard()
                    }

                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXOverline("Did you do all the sets as planned?")
                        choice("Yes, as planned", detail: "Weights move up as usual.", value: true)
                        choice("Not all of it", detail: "It counts as done; your weights stay the same next time.", value: false)
                    }
                    .kxCard()

                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        KXOverline("Time")
                        DurationPicker(seconds: $seconds)
                        DatePicker("Started", selection: $startedAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                            .font(KXFont.body)
                    }
                    .kxCard()

                    KXStepper(label: "Effort", value: $effort, step: 1, range: 1...10, unit: "/10",
                              format: { String(Int($0)) })
                        .frame(maxWidth: .infinity)
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Mark as done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Save session") { save() }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .disabled(allSetsDone == nil)
                    .padding(KXSpacing.screenMargin)
                    .background(KXColor.background)
                    .accessibilityIdentifier("markDone.saveGym")
            }
        }
    }

    private func choice(_ title: String, detail: String, value: Bool) -> some View {
        let selected = allSetsDone == value
        return Button {
            allSetsDone = value
        } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? KXColor.accent : KXColor.inkSecondary)
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        guard let allSetsDone else { return }
        StrengthService.logManual(for: session, allSetsDone: allSetsDone, startedAt: startedAt, durationSeconds: seconds,
                                  effort: effort, units: units, in: context)
        onDone()
        dismiss()
    }
}

/// One line of the session summary in the gym sheet.
private struct StrengthExercisePrescriptionLike {
    let name: String
    let detail: String
}
