import SwiftUI
import TrainingEngine

// MARK: - Inputs

/// Whole numbers typed into a small box ("h", "min", "s").
private struct NumberBox: View {
    let label: String
    @Binding var value: Int
    var width: CGFloat = 56

    var body: some View {
        VStack(spacing: 2) {
            TextField("0", value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(KXFont.number(24, relativeTo: .title2))
                .frame(width: width)
                .padding(.vertical, KXSpacing.xs)
                .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
            Text(label).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }
}

/// A time as hours, minutes and seconds.
struct DurationInput: View {
    @Binding var seconds: Double
    var showsHours = true

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            if showsHours {
                NumberBox(label: "h", value: part(3600, 24))
            }
            NumberBox(label: "min", value: part(60, showsHours ? 60 : 600))
            NumberBox(label: "s", value: part(1, 60))
        }
    }

    /// One of the parts, written back into the total (each part kept in range).
    private func part(_ size: Int, _ limit: Int) -> Binding<Int> {
        Binding {
            let total = Int(seconds.rounded())
            return size == 1 ? total % 60 : (size == 60 ? (showsHours ? (total / 60) % 60 : total / 60) : total / 3600)
        } set: { newValue in
            let value = min(max(newValue, 0), limit - 1)
            let total = Int(seconds.rounded())
            let h = total / 3600, m = showsHours ? (total / 60) % 60 : total / 60, s = total % 60
            switch size {
            case 3600: seconds = Double(value * 3600 + m * 60 + s)
            case 60: seconds = Double((showsHours ? h * 3600 : 0) + value * 60 + s)
            default: seconds = Double((showsHours ? h * 3600 : 0) + m * 60 + value)
            }
        }
    }
}

/// A distance in km or miles, with race presets.
struct DistanceInput: View {
    @Binding var meters: Double
    let units: UnitSystem

    private static let presets: [(String, Double)] = [("5K", 5000), ("10K", 10_000), ("Half", 21_097.5), ("Marathon", 42_195)]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                TextField("0", value: Binding(
                    get: { (Units.distance(meters: meters, in: units) * 100).rounded() / 100 },
                    set: { meters = max(0, $0) * (units == .metric ? 1000 : Units.metersPerMile) }
                ), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .font(KXFont.number(28, relativeTo: .title2))
                    .frame(maxWidth: 140)
                    .padding(.horizontal, KXSpacing.sm)
                    .padding(.vertical, KXSpacing.xs)
                    .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                Text(Units.distanceUnitLabel(units)).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            HStack(spacing: KXSpacing.xs) {
                ForEach(Self.presets, id: \.0) { name, value in
                    KXSelectableChip(text: name, isSelected: abs(meters - value) < 1) { meters = value }
                }
            }
        }
    }
}

private func toolCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: KXSpacing.sm) {
        KXOverline(title)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .kxCard()
}

private func paceText(_ pace: Pace?, _ units: UnitSystem) -> String {
    guard let pace, pace.secondsPerKm > 0, pace.secondsPerKm < 60 * 60 else { return "–" }
    return Units.formatPace(pace, units: units) + Units.paceUnitLabel(units)
}

/// Seconds per km from a pace typed per km or per mile.
private func paceFromInput(_ seconds: Double, _ units: UnitSystem) -> Pace {
    Pace(secondsPerKm: units == .metric ? seconds : seconds / Units.metersPerMile * 1000)
}

private func longTime(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
                         : String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - Pace calculator

/// Pace, time and distance: pick what to work out and enter the other two.
struct PaceCalculatorView: View {
    let units: UnitSystem
    enum Solve: String, CaseIterable, Identifiable { case pace = "Pace", time = "Time", distance = "Distance"; var id: String { rawValue } }
    @State private var solve: Solve = .pace
    @State private var meters: Double = 10_000
    @State private var seconds: Double = 50 * 60
    /// Typed pace, per km or per mile.
    @State private var paceSeconds: Double = 300

    private var pace: Pace { paceFromInput(paceSeconds, units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                Picker("Work out", selection: $solve) {
                    ForEach(Solve.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if solve != .distance { toolCard("Distance") { DistanceInput(meters: $meters, units: units) } }
                if solve != .time { toolCard("Time") { DurationInput(seconds: $seconds) } }
                if solve != .pace {
                    toolCard("Pace (\(Units.paceUnitLabel(units).trimmingCharacters(in: .whitespaces)))") {
                        DurationInput(seconds: $paceSeconds, showsHours: false)
                    }
                }
                result
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Pace calculator")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var result: some View {
        let answer: String
        var detail: String?
        switch solve {
        case .pace:
            let pace = PaceTools.pace(distanceMeters: meters, seconds: seconds)
            answer = paceText(pace, units)
            if let pace { detail = "Treadmill: \(TreadmillSpeed.text(kilometresPerHour: pace.kilometresPerHour, units: units))" }
        case .time:
            answer = meters > 0 && paceSeconds > 0 ? longTime(PaceTools.time(distanceMeters: meters, pace: pace)) : "–"
        case .distance:
            answer = PaceTools.distance(seconds: seconds, pace: pace).map { DisplayFormat(units: units).distance($0, decimals: 2) } ?? "–"
        }
        return VStack(alignment: .leading, spacing: KXSpacing.xs) {
            KXOverline(solve.rawValue, color: KXColor.accent)
            Text(answer).font(KXFont.number(44, relativeTo: .largeTitle)).foregroundStyle(KXColor.ink)
                .accessibilityIdentifier("tools.result")
            if let detail { Text(detail).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxCard()
    }
}

// MARK: - Split planner

/// Splits for a goal time: even, or a negative split (faster second half).
struct SplitPlannerView: View {
    let units: UnitSystem
    enum Strategy: String, CaseIterable, Identifiable {
        case even = "Even", slight = "Slight negative", strong = "Strong negative"
        var id: String { rawValue }
        var fraction: Double { self == .even ? 0 : self == .slight ? 0.02 : 0.04 }
    }
    @State private var meters: Double = 10_000
    @State private var seconds: Double = 50 * 60
    @State private var strategy: Strategy = .even

    private var splits: [PaceTools.PlannedSplit] {
        PaceTools.splits(distanceMeters: meters, goalSeconds: seconds,
                         splitMeters: units == .metric ? 1000 : Units.metersPerMile, negativeSplit: strategy.fraction)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                toolCard("Distance") { DistanceInput(meters: $meters, units: units) }
                toolCard("Goal time") { DurationInput(seconds: $seconds) }
                Picker("Pacing", selection: $strategy) {
                    ForEach(Strategy.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(strategy == .even ? "The same pace all the way."
                     : "Start a little slower and finish faster: the second half about \(Int(strategy.fraction * 100))% quicker than the first. Many runners race best this way.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !splits.isEmpty { splitsCard }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Split planner")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var splitsCard: some View {
        let format = DisplayFormat(units: units)
        let unit = units == .metric ? 1000.0 : Units.metersPerMile
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Text(units == .metric ? "Km" : "Mile").frame(width: 44, alignment: .leading)
                Text("Split").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Pace").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Total").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
            ForEach(splits) { split in
                HStack {
                    Text(split.meters < unit - 1 ? format.shortDistance(split.meters) : "\(split.index)")
                        .frame(width: 44, alignment: .leading).foregroundStyle(KXColor.inkSecondary)
                    Text(longTime(split.seconds)).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(Units.formatPace(split.pace, units: units)).frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(KXColor.inkSecondary)
                    Text(longTime(split.cumulativeSeconds)).frame(maxWidth: .infinity, alignment: .trailing)
                        .font(KXFont.bodyEmphasis.monospacedDigit())
                }
                .font(KXFont.body.monospacedDigit())
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }
}

// MARK: - Converter

/// Pace ↔ treadmill speed, and km ↔ miles.
struct ConverterView: View {
    let units: UnitSystem
    @State private var paceSeconds: Double = 300
    @State private var speedKmh: Double = 12
    @State private var kilometres: Double = 10

    private var pace: Pace { paceFromInput(paceSeconds, units) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                toolCard("Pace → treadmill speed") {
                    DurationInput(seconds: $paceSeconds, showsHours: false)
                    Text(paceSeconds > 0 ? "\(TreadmillSpeed.text(kilometresPerHour: pace.kilometresPerHour, units: .metric)) · \(TreadmillSpeed.text(kilometresPerHour: pace.kilometresPerHour, units: .imperial))" : "–")
                        .font(KXFont.number(30, relativeTo: .title2)).foregroundStyle(KXColor.ink)
                    Text("Per \(units == .metric ? "km" : "mile"). Many runners set a 1% incline to match running outside.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                toolCard("Treadmill speed → pace") {
                    HStack {
                        Stepper(value: $speedKmh, in: 3...30, step: 0.1) {
                            Text(String(format: "%.1f km/h", speedKmh)).font(KXFont.number(26, relativeTo: .title2))
                        }
                    }
                    let fromSpeed = Pace(secondsPerKm: 3600 / speedKmh)
                    Text("\(Units.formatPace(fromSpeed, units: .metric))/km · \(Units.formatPace(fromSpeed, units: .imperial))/mi · \(String(format: "%.1f mph", speedKmh / 1.609344))")
                        .font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                }
                toolCard("Kilometres ↔ miles") {
                    HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
                        TextField("0", value: $kilometres, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .font(KXFont.number(28, relativeTo: .title2))
                            .frame(maxWidth: 120)
                            .padding(.horizontal, KXSpacing.sm)
                            .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                        Text("km =").foregroundStyle(KXColor.inkSecondary)
                        Text(String(format: "%.2f mi", kilometres * 1000 / Units.metersPerMile))
                            .font(KXFont.number(28, relativeTo: .title2))
                    }
                    TextField("Miles", value: Binding(get: { (kilometres * 1000 / Units.metersPerMile * 100).rounded() / 100 },
                                                      set: { kilometres = $0 * Units.metersPerMile / 1000 }),
                              format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .font(KXFont.callout)
                        .padding(KXSpacing.xs)
                        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                    Text("Type in either box.").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Converter")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }
}
