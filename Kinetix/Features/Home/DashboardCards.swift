import SwiftUI
import Charts
import TrainingEngine

// MARK: - Recovery check-in

/// Optional daily check-in: sleep, soreness, energy (1–5). Feeds the balancing logic.
struct CheckInCard: View {
    let existing: RecoveryCheckInModel?
    /// From Apple Health, when connected.
    var restingHeartRate: RestingHeartRateSignal? = nil
    var hrv: HRVSignal? = nil
    /// Hours asleep last night from Apple Health: suggests the sleep score.
    var sleepHours: Double? = nil
    let onSave: (RecoveryCheckIn) -> Void

    @State private var sleep = 3
    @State private var soreness = 2
    @State private var energy = 3
    @State private var editing = false
    /// Once the runner picks a sleep score, Health no longer changes it.
    @State private var sleepChosen = false

    private var sleepBinding: Binding<Int> {
        Binding(get: { sleep }, set: { sleep = $0; sleepChosen = true })
    }

    private func applySleepSuggestion() {
        guard !sleepChosen, let sleepHours else { return }
        sleep = SleepScore.score(hours: sleepHours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            if let existing, !editing {
                // Logged: one slim row (it sits at the bottom of Today by now).
                let checkIn = existing.engineValue(restingHeartRate: restingHeartRate, hrv: hrv)
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(KXColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your score logged").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text("Sleep \(checkIn.sleep) · soreness \(checkIn.soreness) · energy \(checkIn.energy)"
                             + (checkIn.isPoor ? " · plan eased" : ""))
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer(minLength: KXSpacing.sm)
                    Button("Edit") {
                        sleep = existing.sleep; soreness = existing.soreness; energy = existing.energy
                        sleepChosen = true
                        editing = true
                    }
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.accent)
                }
                .accessibilityElement(children: .combine)
            } else {
                KXSectionHeader("Your score", subtitle: "How do you feel today? Optional")
                if let restingHeartRate { restingHeartRateLine(restingHeartRate) }
                if let hrv { hrvLine(hrv) }
                ratingRow("Sleep", value: sleepBinding, low: "Poor", high: "Great", symbol: "moon.zzz")
                if let sleepHours, !sleepChosen {
                    Label("\(HealthMetric.sleep.format(sleepHours)) asleep in Apple Health, so \(SleepScore.score(hours: sleepHours)) is suggested",
                          systemImage: "bed.double.fill")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("checkIn.sleepSuggestion")
                }
                ratingRow("Soreness", value: $soreness, low: "None", high: "Very", symbol: "bandage")
                ratingRow("Energy", value: $energy, low: "Drained", high: "Buzzing", symbol: "bolt")
                Button("Save my score") {
                    onSave(RecoveryCheckIn(sleep: sleep, soreness: soreness, energy: energy))
                    editing = false
                }
                .buttonStyle(.kx(.secondary, fullWidth: true))
            }
        }
        .kxCard()
        .onAppear(perform: applySleepSuggestion)
        .onChange(of: sleepHours) { _, _ in applySleepSuggestion() }
    }

    private func hrvLine(_ signal: HRVSignal) -> some View {
        Label {
            Text("HRV \(signal.description)")
        } icon: {
            Image(systemName: signal.isSuppressed ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                .foregroundStyle(signal.isSuppressed ? KXColor.warning : KXColor.inkSecondary)
        }
        .font(KXFont.caption)
        .foregroundStyle(KXColor.ink)
        .accessibilityLabel("Heart rate variability \(signal.description)\(signal.isSuppressed ? ", lower than usual" : "")")
    }

    private func restingHeartRateLine(_ signal: RestingHeartRateSignal) -> some View {
        Label {
            Text("Resting HR \(signal.description)")
        } icon: {
            Image(systemName: signal.isElevated ? "exclamationmark.triangle.fill" : "heart.fill")
                .foregroundStyle(signal.isElevated ? KXColor.warning : KXColor.inkSecondary)
        }
        .font(KXFont.caption)
        .foregroundStyle(KXColor.ink)
        .accessibilityLabel("Resting heart rate \(signal.description)\(signal.isElevated ? ", higher than usual" : "")")
    }

    /// A 1–5 slider with the value beside it and what each end means underneath.
    private func ratingRow(_ title: String, value: Binding<Int>, low: String, high: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(KXFont.number(24, relativeTo: .title3))
                    .foregroundStyle(KXColor.ink)
                Text("/5").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }),
                   in: 1...5, step: 1)
                .tint(KXColor.accent)
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue) of 5")
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(KXFont.caption)
            .foregroundStyle(KXColor.inkTertiary)
            .accessibilityHidden(true)
        }
    }
}
