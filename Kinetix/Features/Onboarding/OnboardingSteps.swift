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
        Option(goal: .faster10k, detail: "Get quicker over 10K.", symbol: "stopwatch"),
        Option(goal: .halfMarathon, detail: "Train for 21.1 km.", symbol: "road.lanes"),
        Option(goal: .marathon, detail: "Train for 42.2 km.", symbol: "medal"),
        Option(goal: .buildStrength, detail: "Lift heavier, with running for fitness.", symbol: "scalemass"),
        Option(goal: .buildMuscle, detail: "Add muscle while keeping your engine.", symbol: "figure.strengthtraining.functional")
    ]

    var body: some View {
        OnboardingQuestion(plain: "Your primary", accented: "goal", detail: "Your plan protects the sessions that matter most for this.")
        VStack(spacing: KXSpacing.md) {
            ForEach(options) { option in
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
    var body: some View {
        OnboardingQuestion(plain: "Almost", accented: "there", detail: "Two more things will be set up as the app grows:")
        VStack(spacing: KXSpacing.md) {
            infoCard(
                symbol: "person.crop.circle.badge.checkmark",
                title: "Your account",
                text: "Sign in with Apple or email will back up and sync your training across devices. For now everything is saved on this iPhone and works without signal."
            )
            infoCard(
                symbol: "heart.text.square",
                title: "Apple Health",
                text: "We'll ask to read heart rate, resting heart rate and workouts (for live heart rate and to balance your training load) and to save your runs and lifts. You choose exactly what to share."
            )
        }
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
