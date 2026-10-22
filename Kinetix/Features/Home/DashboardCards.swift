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
                let checkIn = existing.engineValue(restingHeartRate: restingHeartRate, hrv: hrv)
                HStack(alignment: .top, spacing: KXSpacing.lg) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(KXColor.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXSectionHeader("Your score")
                        Text("Sleep \(checkIn.sleep)/5 \u{00B7} soreness \(checkIn.soreness)/5 \u{00B7} energy \(checkIn.energy)/5")
                            .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text(checkIn.isPoor
                             ? "Logged and counted in your recovery. You're feeling run down, so today's plan has been eased where it can be."
                             : "Logged and counted in your recovery.")
                            .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let restingHeartRate { restingHeartRateLine(restingHeartRate) }
                        if let hrv { hrvLine(hrv) }
                        Button("Update") {
                            sleep = existing.sleep; soreness = existing.soreness; energy = existing.energy
                            sleepChosen = true
                            editing = true
                        }
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.accent)
                    }
                }
            } else {
                KXSectionHeader("Your score", subtitle: "How are you today? Optional · helps balance your training")
                if let restingHeartRate { restingHeartRateLine(restingHeartRate) }
                if let hrv { hrvLine(hrv) }
                ratingRow("Sleep", value: sleepBinding, low: "Poor", high: "Great", symbol: "moon.zzz")
                if let sleepHours, !sleepChosen {
                    Label("Apple Health: \(HealthMetric.sleep.format(sleepHours)) asleep, so \(SleepScore.score(hours: sleepHours))/5 is suggested. Change it if it felt different.",
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

    private func ratingRow(_ title: String, value: Binding<Int>, low: String, high: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack {
                Label(title, systemImage: symbol).font(KXFont.callout).foregroundStyle(KXColor.ink)
                Spacer()
                Text("\(low) → \(high)").font(.caption2).foregroundStyle(KXColor.inkTertiary)
            }
            HStack(spacing: KXSpacing.xs) {
                ForEach(1...5, id: \.self) { rating in
                    KXSelectableChip(text: "\(rating)", isSelected: value.wrappedValue == rating) { value.wrappedValue = rating }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(title) \(rating) of 5")
                }
            }
        }
    }
}
