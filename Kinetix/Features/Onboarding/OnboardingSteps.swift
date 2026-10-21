import SwiftUI
import TrainingEngine

struct UnitsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "How do you", accented: "measure?", detail: "You can change this any time in Settings.")
        VStack(spacing: KXSpacing.md) {
            KXOptionCard(title: "Kilometres & kilograms", detail: "Pace per km, weights in kg", systemImage: "ruler",
                         isSelected: model.units == .metric) { model.units = .metric }
            KXOptionCard(title: "Miles & pounds", detail: "Pace per mile, weights in lb", systemImage: "ruler.fill",
                         isSelected: model.units == .imperial) { model.units = .imperial }
        }
    }
}

struct AgeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "How", accented: "old are you?",
                           detail: "Your age gives a starting estimate of your max heart rate, which sets your heart-rate zones. Kinetix updates it from your runs, and you can set your own zones in Settings.")
        VStack(spacing: KXSpacing.md) {
            KXStepper(label: "Age",
                      value: Binding(get: { Double(model.age) }, set: { model.age = Int($0); model.knowsAge = true }),
                      step: 1, range: 13...100, format: { String(format: "%.0f", $0) })
                .frame(maxWidth: .infinity)
            Text("Estimated max heart rate: \(Int(HeartRateZones.ageEstimate(age: model.age))) bpm")
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
        }
        .kxCard()
        .onAppear { model.knowsAge = true }
    }
}

struct RunningExperienceStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "Your running", accented: "experience", detail: "This sets your starting mileage and how hard your sessions are.")
        VStack(spacing: KXSpacing.md) {
            KXOptionCard(title: "Beginner", detail: "New to running, or under about 10 km a week.", systemImage: "figure.walk",
                         isSelected: model.runningExperience == .beginner) { model.runningExperience = .beginner }
            KXOptionCard(title: "Intermediate", detail: "Running regularly, 15–35 km a week; done a race or two.", systemImage: "figure.run",
                         isSelected: model.runningExperience == .intermediate) { model.runningExperience = .intermediate }
            KXOptionCard(title: "Advanced", detail: "Consistent training over 35 km a week with structured sessions.", systemImage: "hare",
                         isSelected: model.runningExperience == .advanced) { model.runningExperience = .advanced }
        }
    }
}

struct RaceTimeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "A recent", accented: "race time?",
                           detail: "Optional. A recent race or a comfortable time trial sets your pace zones accurately. Skip and we'll estimate from your experience.")
        Toggle("I have a recent time", isOn: $model.knowsRaceTime)
            .font(KXFont.bodyEmphasis)
            .tint(KXColor.accent)
            .kxCard()
        if model.knowsRaceTime {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                KXOverline("Distance")
                Picker("Distance", selection: $model.raceDistance) {
                    ForEach(OnboardingModel.RaceDistance.allCases) { distance in
                        Text(distance.label).tag(distance)
                    }
                }
                .pickerStyle(.segmented)
                KXOverline("Time")
                HStack(spacing: 0) {
                    timeWheel("Hours", selection: $model.raceHours, range: 0...6)
                    timeWheel("Minutes", selection: $model.raceMinutes, range: 0...59)
                    timeWheel("Seconds", selection: $model.raceSeconds, range: 0...59)
                }
                .frame(height: 150)
                if model.raceTimeSeconds >= 600 {
                    let zones = PaceZones(race: RaceResult(distanceMeters: model.raceDistance.rawValue, timeSeconds: model.raceTimeSeconds))
                    Text("Easy pace about \(paceText(zones.typicalPace(for: .easy))), tempo about \(paceText(zones.typicalPace(for: .threshold))).")
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .kxCard()
        }
    }

    private func paceText(_ pace: Pace) -> String {
        Units.formatPace(pace, units: model.units) + Units.paceUnitLabel(model.units)
    }

    private func timeWheel(_ label: String, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(Array(range), id: \.self) { value in
                Text("\(value) \(label.prefix(1).lowercased())").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityLabel(label)
    }
}

struct CurrentRunningStep: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context

    private var unit: String { Units.distanceUnitLabel(model.units) }
    private var metersPerUnit: Double { model.units == .imperial ? 1609.344 : 1000 }

    /// A distance in whole kilometres or miles, stored in metres.
    private func distance(_ meters: ReferenceWritableKeyPath<OnboardingModel, Double>) -> Binding<Int> {
        Binding(get: { Int((model[keyPath: meters] / metersPerUnit).rounded()) },
                set: { model[keyPath: meters] = Double($0) * metersPerUnit })
    }

    var body: some View {
        OnboardingQuestion(plain: "Your running", accented: "right now",
                           detail: "Optional. Your plan starts from what you already run, so experienced runners don't start too easy and newer runners don't start too hard.")
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXOverline("In a typical week")
            Stepper(value: distance(\.weeklyRunMeters), in: 0...200) {
                HStack(spacing: KXSpacing.xs) {
                    KXEditableNumber(display: "\(distance(\.weeklyRunMeters).wrappedValue)", allowsDecimal: false,
                                     accessibilityLabel: "Distance in a typical week") { typed in
                        distance(\.weeklyRunMeters).wrappedValue = min(max(Int(typed), 0), 200)
                    }
                    Text(model.weeklyRunMeters < 1 ? "\(unit) · not running yet" : unit)
                        .font(KXFont.bodyEmphasis)
                }
            }
            .accessibilityIdentifier("onboarding.weeklyRun")
            if model.weeklyRunMeters >= 1 {
                Divider()
                KXOverline("Longest run in the last month")
                Stepper(value: distance(\.longestRunMeters), in: 1...60) {
                    HStack(spacing: KXSpacing.xs) {
                        KXEditableNumber(display: "\(distance(\.longestRunMeters).wrappedValue)", allowsDecimal: false,
                                         accessibilityLabel: "Longest run") { typed in
                            distance(\.longestRunMeters).wrappedValue = min(max(Int(typed), 1), 60)
                        }
                        Text(unit).font(KXFont.bodyEmphasis)
                    }
                }
                .accessibilityIdentifier("onboarding.longestRun")
            }
        }
        .kxCard()
        .onChange(of: model.weeklyRunMeters) { model.knowsCurrentRunning = true }
        .onChange(of: model.longestRunMeters) { model.knowsCurrentRunning = true }
        if let history = model.recentHistory {
            let weekly = Int(Units.distance(meters: history.weeklyMeters, in: model.units).rounded())
            let longest = Int(Units.distance(meters: history.longestMeters, in: model.units).rounded())
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Label("From your last 4 weeks (\(history.runCount) runs in Kinetix, Strava and Apple Health): about \(weekly) \(unit) a week, longest \(longest) \(unit).",
                      systemImage: "clock.arrow.circlepath")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                if !model.applyHistoryAutomatically {
                    Button("Use these") { model.useHistory() }
                        .buttonStyle(.kx(.secondary))
                }
            }
        } else {
            Text("Not sure? Skip and we'll start you at a sensible level for your experience.")
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
        }
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            Toggle("I've raced in the last two weeks", isOn: $model.racedRecently)
                .font(KXFont.bodyEmphasis)
                .accessibilityIdentifier("onboarding.racedRecently")
            if model.racedRecently {
                Toggle("Start with an easy week", isOn: $model.easyFirstWeek)
                    .font(KXFont.bodyEmphasis)
                Text("Your answer here is the only thing that decides whether your plan starts with an easy week: easy running only, then your programme.")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
        }
        .tint(KXColor.accent)
        .kxCard()
        .task {
            guard model.recentHistory == nil, let history = PlanService.recentRunning(in: context) else { return }
            model.recentHistory = history
            if model.applyHistoryAutomatically { model.useHistory() }
        }
    }
}

struct LiftingExperienceStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "Your lifting", accented: "experience", detail: "This sets your exercise choice, volume and starting weights.")
        VStack(spacing: KXSpacing.md) {
            KXOptionCard(title: "Beginner", detail: "Little or no regular weight training.", systemImage: "dumbbell",
                         isSelected: model.liftingExperience == .beginner) { model.liftingExperience = .beginner }
            KXOptionCard(title: "Intermediate", detail: "Lifting consistently for 6+ months; comfortable with squats and presses.", systemImage: "dumbbell.fill",
                         isSelected: model.liftingExperience == .intermediate) { model.liftingExperience = .intermediate }
            KXOptionCard(title: "Advanced", detail: "Years of structured strength training.", systemImage: "figure.strengthtraining.traditional",
                         isSelected: model.liftingExperience == .advanced) { model.liftingExperience = .advanced }
        }
    }
}

struct LiftEstimatesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "Know your", accented: "numbers?",
                           detail: "Optional. Enter a weight you can lift for a given number of reps (or a 1-rep max) and we'll set your starting weights from it.")
        VStack(spacing: KXSpacing.md) {
            ForEach($model.liftEntries) { $entry in
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    Toggle(entry.lift.displayName, isOn: $entry.isKnown)
                        .font(KXFont.bodyEmphasis)
                        .tint(KXColor.accent)
                    if entry.isKnown {
                        HStack(spacing: KXSpacing.sm) {
                            KXStepper(
                                label: "Weight",
                                value: displayWeight($entry.weightKg),
                                step: model.units == .metric ? 2.5 : 5,
                                range: 0...500,
                                unit: Units.weightUnitLabel(model.units),
                                format: { String(format: "%g", $0) }
                            )
                            KXStepper(label: "Reps", value: $entry.reps, step: 1, range: 1...20, format: { String(format: "%.0f", $0) })
                        }
                    }
                }
                .kxCard()
            }
        }
    }

    /// Shows kg or lb while storing kg.
    private func displayWeight(_ kg: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { model.units == .metric ? kg.wrappedValue : (Units.kgToLb(kg.wrappedValue) / 5).rounded() * 5 },
            set: { kg.wrappedValue = model.units == .metric ? $0 : Units.lbToKg($0) }
        )
    }
}

struct GoalStep: View {
    @Bindable var model: OnboardingModel

    private struct Option: Identifiable {
        let goal: TrainingGoal
        let detail: String
        let symbol: String
        var id: TrainingGoal { goal }
    }

    private let options: [Option] = [
        Option(goal: .balancedHybrid, detail: "Run and lift in equal measure: better at both.", symbol: "figure.mixed.cardio"),
        Option(goal: .first5k, detail: "Build up to running 5K, with strength to stay injury-free.", symbol: "flag"),
        Option(goal: .faster5k, detail: "Get quicker over 5K.", symbol: "hare"),
        Option(goal: .faster10k, detail: "Get quicker over 10K.", symbol: "stopwatch"),
        Option(goal: .halfMarathon, detail: "Train for 21.1 km.", symbol: "road.lanes"),
        Option(goal: .marathon, detail: "Train for 42.2 km.", symbol: "medal"),
        Option(goal: .buildStrength, detail: "Lift heavier, with running for fitness.", symbol: "scalemass"),
        Option(goal: .buildMuscle, detail: "Add muscle while keeping your engine.", symbol: "figure.strengthtraining.functional")
    ]

    /// The goals for their running experience (set in the programmes workbook), plus their
    /// current goal so it's never hidden from them.
    private var visibleOptions: [Option] {
        let level = model.runningExperience ?? .beginner
        return options.filter { PlanService.templates.programmes.isGoal($0.goal, availableTo: level) || model.goal == $0.goal }
    }

    var body: some View {
        OnboardingQuestion(plain: "Your primary", accented: "goal", detail: "Your plan is built around this.")
        VStack(spacing: KXSpacing.md) {
            ForEach(visibleOptions) { option in
                KXOptionCard(title: option.goal.displayName, detail: option.detail, systemImage: option.symbol,
                             isSelected: model.goal == option.goal) {
                    model.goal = option.goal
                }
            }
        }
    }
}

struct EventDateStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "Training for", accented: "an event?",
                           detail: "Optional. With a date, your plan builds through base, build and peak phases, then tapers so you arrive fresh.")
        Toggle("I have a target date", isOn: $model.hasEvent)
            .font(KXFont.bodyEmphasis)
            .tint(KXColor.accent)
            .kxCard()
        if model.hasEvent {
            DatePicker(
                "Event date",
                selection: $model.eventDate,
                in: Date.now...(Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(KXColor.accent)
            .kxCard()
        }
    }
}

struct GymWeekStep: View {
    @Bindable var model: OnboardingModel

    private var strength: WorkbookStrength? { PlanService.templates.programmes.strength }
    private var suggested: String? { model.goal.flatMap { PlanService.templates.programmes.settings(for: $0)?.defaultSplit } }
    private var offered: [WorkbookSplit] { strength?.offered(sessions: model.liftSessionsPerWeek) ?? [] }

    var body: some View {
        OnboardingQuestion(plain: "Your gym", accented: "week",
                           detail: "How many gym sessions a week, and how you'd like to split them. Your plan puts leg days away from your hardest runs.")
        KXStepper(label: "Gym sessions per week",
                  value: Binding(get: { Double(model.liftSessionsPerWeek) }, set: { model.liftSessionsPerWeek = Int($0) }),
                  step: 1, range: 0...6, format: { String(format: "%.0f", $0) })
            .frame(maxWidth: .infinity)
        if model.liftSessionsPerWeek == 0 {
            Text("No gym sessions: your plan is running only.")
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
        } else {
            VStack(spacing: KXSpacing.md) {
                ForEach(offered) { split in
                    KXOptionCard(title: split.code == suggested ? "\(split.name) · Suggested" : split.name,
                                 detail: days(of: split) + (split.suits.isEmpty ? "" : "\n" + split.suits),
                                 systemImage: "dumbbell",
                                 isSelected: model.splitCode == split.code) {
                        model.splitCode = split.code
                    }
                }
            }
        }
        // A zero-height view (EmptyView doesn't run onAppear).
        Color.clear.frame(height: 0)
            .onAppear {
                if !model.gymWeekChosen {
                    // Start from the goal's suggested split.
                    if let code = suggested, let split = strength?.split(code) {
                        model.liftSessionsPerWeek = split.days.count
                        model.splitCode = code
                    }
                    model.gymWeekChosen = true
                }
                pickSplitIfNeeded()
            }
            .onChange(of: model.liftSessionsPerWeek) { pickSplitIfNeeded() }
    }

    /// e.g. "Push · Pull · Legs" (the days used for this many sessions).
    private func days(of split: WorkbookSplit) -> String {
        let count = model.liftSessionsPerWeek
        return (0..<count).map { split.days[$0 % split.days.count].name }.joined(separator: " · ")
    }

    /// Keeps a split selected that fits the number of sessions.
    private func pickSplitIfNeeded() {
        guard model.liftSessionsPerWeek > 0, !offered.contains(where: { $0.code == model.splitCode }) else { return }
        model.splitCode = offered.first(where: { $0.code == suggested })?.code ?? offered.first?.code
    }
}

/// "That's 7 sessions on 5 days" when runs and gym sessions don't fit the training days.
struct ScheduleFitWarning: View {
    let model: OnboardingModel

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(KXFont.callout)
                .foregroundStyle(KXColor.ink)
                .symbolRenderingMode(.multicolor)
                .kxCard(.accent)
                .accessibilityIdentifier("onboarding.fitWarning")
        }
    }

    private var message: String? {
        guard model.gymWeekChosen, let goal = model.goal else { return nil }
        let profile = model.profile
        let runsWanted = PlanService.templates.programmes.settings(for: goal)?.runsMin ?? (goal.isRunningFocused ? 3 : 1)
        let liftsWanted = model.liftSessionsPerWeek
        let counts = PlanService.generator.weeklyMixCounts(for: profile)
        guard counts.runs < runsWanted || counts.lifts < liftsWanted else { return nil }
        let days = model.trainingDays.count
        let doubles = model.doubleSessionDays
        let place = "\(days) training day\(days == 1 ? "" : "s")" + (doubles > 0 ? " with \(doubles) double\(doubles == 1 ? "" : "s")" : "")
        return "That's \(runsWanted + liftsWanted) sessions (\(runsWanted) runs, \(liftsWanted) gym) on \(place). "
            + "Your plan will have \(counts.runs) run\(counts.runs == 1 ? "" : "s") and \(counts.lifts) gym session\(counts.lifts == 1 ? "" : "s"). "
            + "To fit everything, add a training day, add a double day, or choose fewer gym sessions."
    }
}

struct TrainingDaysStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "Your training", accented: "days", detail: "Pick the days you can train (2 to 7). Days you leave out stay as rest days.")
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: KXSpacing.sm)], spacing: KXSpacing.sm) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    KXSelectableChip(text: day.shortName, isSelected: model.trainingDays.contains(day)) {
                        if model.trainingDays.contains(day) {
                            model.trainingDays.remove(day)
                        } else {
                            model.trainingDays.insert(day)
                        }
                    }
                }
            }
            Text(daysCaption)
                .font(KXFont.callout)
                .foregroundStyle(model.trainingDays.count < 2 ? KXColor.danger : KXColor.inkSecondary)
        }
        .kxCard()
        ScheduleFitWarning(model: model)
    }

    private var daysCaption: String {
        switch model.trainingDays.count {
        case 0, 1: return "Choose at least two days."
        case 7: return "7 days selected. We'll still keep one full rest day so you can recover."
        default: return "\(model.trainingDays.count) days a week."
        }
    }
}

struct DoubleSessionsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "Any double", accented: "sessions?",
                           detail: "On how many days could you train twice (for example a morning run and an evening lift)? Doubles let us keep hard days hard and easy days easy.")
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXStepper(
                label: "Double days per week",
                value: Binding(get: { Double(model.doubleSessionDays) }, set: { model.doubleSessionDays = Int($0) }),
                step: 1,
                range: 0...Double(model.maxDoubleDays),
                format: { String(format: "%.0f", $0) }
            )
            .frame(maxWidth: .infinity)
            Text(model.doubleSessionDays == 0 ? "One session a day." : "Up to \(model.doubleSessionDays) day\(model.doubleSessionDays == 1 ? "" : "s") with two sessions.")
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
        }
        .kxCard()
        ScheduleFitWarning(model: model)
    }
}

struct EquipmentStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingQuestion(plain: "Your", accented: "equipment", detail: "We'll choose exercises that suit what you have.")
        VStack(spacing: KXSpacing.md) {
            KXOptionCard(title: "Full gym", detail: "Barbells, racks, machines and cables.", systemImage: "building.2",
                         isSelected: model.equipment == .fullGym) { model.equipment = .fullGym }
            KXOptionCard(title: "Home gym", detail: "Barbell and rack, dumbbells, bench, pull-up bar.", systemImage: "house",
                         isSelected: model.equipment == .homeGym) { model.equipment = .homeGym }
            KXOptionCard(title: "Dumbbells only", detail: "A set of dumbbells (adjustable is ideal).", systemImage: "dumbbell",
                         isSelected: model.equipment == .dumbbellsOnly) { model.equipment = .dumbbellsOnly }
            KXOptionCard(title: "Bodyweight", detail: "No equipment needed.", systemImage: "figure.cooldown",
                         isSelected: model.equipment == .bodyweight) { model.equipment = .bodyweight }
        }
    }
}

struct FinishStep: View {
    @Bindable var model: OnboardingModel
    @State private var auth = AuthService.shared
    @State private var health = HealthService.shared
    @State private var integrations = IntegrationSettings.shared
    @State private var showAccount = false
    @State private var showHealthNotice = false

    var body: some View {
        OnboardingQuestion(plain: "Almost", accented: "there", detail: "Two optional extras, and one thing to read, before we build your plan:")
        VStack(spacing: KXSpacing.md) {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                infoCard(
                    symbol: "person.crop.circle.badge.checkmark",
                    title: "Your account",
                    text: auth.isSignedIn
                        ? "Signed in\(auth.email.map { " as \($0)" } ?? ""). Your training is backed up and syncs across your devices."
                        : "Back up your training and sync it across devices with Sign in with Apple or email. Optional: everything works on this iPhone without one, even without signal."
                )
                if auth.state == .signedOut {
                    Button("Create an account") { showAccount = true }
                        .buttonStyle(.kx(.secondary, fullWidth: true))
                }
            }
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                infoCard(
                    symbol: "heart.text.square",
                    title: "Apple Health",
                    text: integrations.healthEnabled
                        ? "Connected. Your sessions are saved to Health, and heart rate and resting heart rate help balance your training."
                        : "Optional: save your runs and lifts to Health, see Apple Watch heart rate during runs, and let resting heart rate and other workouts balance your load. You choose exactly what to share."
                )
                if health.isAvailable && !integrations.healthEnabled {
                    Button("Connect Apple Health") { Task { await connectHealth() } }
                        .buttonStyle(.kx(.secondary, fullWidth: true))
                }
            }
            healthNotice
        }
        .sheet(isPresented: $showAccount) { AuthView(mode: .create) }
        .sheet(isPresented: $showHealthNotice) {
            NavigationStack {
                HealthDisclaimerView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHealthNotice = false } } }
            }
        }
    }

    /// Required acknowledgement: Kinetix is training guidance, not medical advice.
    private var healthNotice: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            infoCard(
                symbol: "cross.case",
                title: "Train safely",
                text: "Kinetix gives general training guidance, not medical advice. Check with a doctor before starting a new programme if you have a medical condition, injury or are pregnant, and stop if you feel chest pain, faint or unwell."
            )
            Button("Read the full health & safety notes") { showHealthNotice = true }
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.accent)
            Button {
                model.acceptedHealthNotice.toggle()
            } label: {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    Image(systemName: model.acceptedHealthNotice ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(model.acceptedHealthNotice ? KXColor.accent : KXColor.inkSecondary)
                    Text("I understand and I'm fit to start training")
                        .font(KXFont.bodyEmphasis)
                        .foregroundStyle(KXColor.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.healthNotice")
            .accessibilityValue(model.acceptedHealthNotice ? "Checked" : "Not checked")
            .accessibilityAddTraits(model.acceptedHealthNotice ? .isSelected : [])
        }
    }

    private func connectHealth() async {
        guard (try? await health.requestAuthorization()) != nil else { return }
        integrations.healthEnabled = true
        integrations.healthConnectedAt = .now
    }

    private func infoCard(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(KXColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(title).font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text(text).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .kxCard()
        .accessibilityElement(children: .combine)
    }
}
