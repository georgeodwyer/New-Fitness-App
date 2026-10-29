import SwiftUI
import Charts
import TrainingEngine

// MARK: - Strain and recovery

/// Today's recovery dial, exertion against today's target, and the readings behind
/// recovery (HRV, resting heart rate, sleep). Tap for the full breakdown.
struct StrainCard: View {
    let report: StrainReport
    /// Last night's Health data isn't in yet, so there's no recovery score.
    var isWaitingForLastNight = false

    @ScaledMetric(relativeTo: .largeTitle) private var dialSize: CGFloat = 206
    @State private var showDetail = false

    private var strain: Double { report.today.strain }
    private var target: StrainTarget { report.target }

    @State private var health = HealthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            RecoveryDial(recovery: report.recovery, isWaitingForLastNight: isWaitingForLastNight)
                .frame(width: dialSize, height: dialSize * 0.86)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("dashboard.recoveryBreakdown")
            if isWaitingForLastNight {
                VStack(spacing: KXSpacing.xs) {
                    Button {
                        health.stopWaitingForSleep()
                    } label: {
                        Label("Don't wait: use my check-in", systemImage: "hand.raised")
                    }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
                    .accessibilityIdentifier("dashboard.stopWaiting")
                    Text("No sleep data yet (watch charging overnight?). Get a score now from your check-in and anything Health has; sleep is added if it arrives later.")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            exertion
            let readings = RecoveryReading.live(health: health, recovery: report.recovery, waiting: isWaitingForLastNight)
            if !readings.isEmpty {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    ForEach(readings) { reading in
                        reading.view.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            HStack(spacing: KXSpacing.sm) {
                KXOverline("Legs")
                KXStatusPill(level: TodayFormat.legsLevel(report.legs.status), text: report.legs.status.title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.inkTertiary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
        .kxCard()
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Show what's behind your recovery and exertion") { showDetail = true }
        .accessibilityIdentifier("dashboard.exertion")
        .sheet(isPresented: $showDetail) {
            TodayBodyDetailView(report: report, isWaitingForLastNight: isWaitingForLastNight)
                .presentationDetents([.large])
        }
    }

    private var exertion: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                KXOverline("Exertion today")
                Spacer(minLength: KXSpacing.sm)
                (Text(TodayFormat.one(strain)).font(KXFont.custom(.bold, 13, relativeTo: .caption)).foregroundColor(KXColor.ink)
                    + Text(" · target \(TodayFormat.one(target.low))–\(TodayFormat.one(target.high))")
                    .font(KXFont.caption).foregroundColor(KXColor.inkSecondary))
            }
            ExertionBar(strain: strain, target: target)
                .frame(height: 10)
            Text(TodayFormat.status(strain: strain, target: target))
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exertion today \(TodayFormat.one(strain)) of 100")
        .accessibilityValue("Target \(TodayFormat.one(target.low)) to \(TodayFormat.one(target.high)). \(TodayFormat.status(strain: strain, target: target))")
    }
}

/// A 270° dial for today's recovery: red to amber to green, a marker at the score and the
/// score itself in plain text.
struct RecoveryDial: View {
    let recovery: RecoveryScore?
    var isWaitingForLastNight = false

    private static let sweep = 0.75
    private static let startAngle = 135.0

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height / 0.86)
            let line = size * 0.075
            let radius = (size - line) / 2 - 4
            let center = CGPoint(x: geo.size.width / 2, y: size / 2)
            let share = min(max((recovery?.score ?? 0) / 100, 0), 1)
            let gradient = AngularGradient(colors: [KXColor.danger, KXColor.warning, KXColor.success],
                                           center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * Self.sweep))
            ZStack {
                Circle()
                    .trim(from: 0, to: Self.sweep)
                    .stroke(KXColor.border, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(Self.startAngle))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                if recovery != nil {
                    // A soft glow under the coloured part.
                    Circle()
                        .trim(from: 0, to: Self.sweep * share)
                        .stroke(gradient, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(Self.startAngle))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                        .blur(radius: line * 0.6)
                        .opacity(0.5)
                    Circle()
                        .trim(from: 0, to: Self.sweep * share)
                        .stroke(gradient, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(Self.startAngle))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    let angle = (Self.startAngle + 360 * Self.sweep * share) * .pi / 180
                    Circle()
                        .fill(KXColor.surface)
                        .overlay(Circle().stroke(KXColor.ink, lineWidth: line * 0.3))
                        .frame(width: line * 1.15, height: line * 1.15)
                        .position(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                }
                VStack(spacing: 2) {
                    KXOverline("Recovery")
                    if let recovery {
                        Text("\(Int(recovery.score))")
                            .font(KXFont.number(size * 0.3, relativeTo: .largeTitle))
                            .foregroundStyle(KXColor.ink)
                        Text(TodayFormat.headline(recovery.band))
                            .font(KXFont.captionEmphasis)
                            .foregroundStyle(TodayFormat.color(recovery.band))
                    } else {
                        Text("–")
                            .font(KXFont.number(size * 0.3, relativeTo: .largeTitle))
                            .foregroundStyle(KXColor.inkTertiary)
                        Text(isWaitingForLastNight ? "Waiting for last night's sleep" : "Not yet")
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: radius * 1.5)
                .position(center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recovery.map { "Recovery \(Int($0.score)), \(TodayFormat.headline($0.band))" }
                            ?? (isWaitingForLastNight ? "Recovery: waiting for last night's sleep" : "Recovery not yet available"))
    }
}

/// Today's exertion (0–100) on a bar, with today's target range drawn as a dashed box.
struct ExertionBar: View {
    let strain: Double
    let target: StrainTarget
    @Environment(\.colorScheme) private var scheme

    private func share(_ value: Double) -> CGFloat { CGFloat(min(max(value / Strain.maximum, 0), 1)) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(KXColor.surfaceTint)
                Capsule()
                    .fill(strain > target.high
                          ? AnyShapeStyle(KXColor.warning)
                          : scheme == .dark ? AnyShapeStyle(LinearGradient(colors: [KXColor.run, KXColor.accent], startPoint: .leading, endPoint: .trailing))
                                            : AnyShapeStyle(KXColor.accent))
                    .frame(width: max(height, width * share(strain)))
                    .opacity(strain > 0 ? 1 : 0)
                Capsule()
                    .strokeBorder(KXColor.inkSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: max(height, width * (share(target.high) - share(target.low))), height: height + 8)
                    .offset(x: width * share(target.low))
            }
        }
    }
}

/// One reading behind recovery for the row under the dial: "61 ms · ▲ 4% vs usual".
struct RecoveryReading: Identifiable {
    let label: String
    let value: String
    let unit: String
    let note: String
    let noteColor: Color
    var id: String { label }

    var view: some View {
        VStack(alignment: .leading, spacing: 1) {
            KXOverline(label)
            (Text(value).font(KXFont.number(24, relativeTo: .title3)).foregroundColor(KXColor.ink)
                + Text(unit.isEmpty ? "" : " " + unit).font(KXFont.caption).foregroundColor(KXColor.inkSecondary))
            Text(note)
                .font(KXFont.captionEmphasis)
                .foregroundStyle(noteColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    /// HRV, resting heart rate and last night's sleep, straight from Health, so they show even
    /// before there's a score. Without Health, the parts of the recovery score (check-in).
    @MainActor
    static func live(health: HealthService, recovery: RecoveryScore?, waiting: Bool) -> [RecoveryReading] {
        guard health.isConnected else { return recovery.map(readings) ?? [] }
        let missing = waiting ? "waiting" : "no reading"
        var result: [RecoveryReading] = []
        if let hrv = health.hrv {
            let percent = hrv.baseline > 0 ? Int(((hrv.today / hrv.baseline - 1) * 100).rounded()) : 0
            result.append(RecoveryReading(label: "HRV", value: "\(Int(hrv.today.rounded()))", unit: "ms",
                                          note: percent == 0 ? "Your usual" : "\(percent > 0 ? "▲" : "▼") \(abs(percent))% vs usual",
                                          noteColor: percent == 0 ? KXColor.inkSecondary : (percent > 0 ? KXColor.success : KXColor.warning)))
        } else {
            result.append(RecoveryReading(label: "HRV", value: "–", unit: "", note: missing, noteColor: KXColor.inkSecondary))
        }
        if let rhr = health.restingHeartRate {
            let delta = Int(rhr.difference.rounded())
            result.append(RecoveryReading(label: "Resting HR", value: "\(Int(rhr.today.rounded()))", unit: "bpm",
                                          note: delta == 0 ? "Your usual" : "\(delta < 0 ? "▼" : "▲") \(abs(delta)) bpm",
                                          noteColor: delta == 0 ? KXColor.inkSecondary : (delta < 0 ? KXColor.success : KXColor.warning)))
        } else {
            result.append(RecoveryReading(label: "Resting HR", value: "–", unit: "", note: missing, noteColor: KXColor.inkSecondary))
        }
        if let hours = health.lastNightSleepHours {
            let minutes = Int((hours * 60).rounded())
            let note = health.usualSleepHours.map { "\(Int((hours / $0 * 100).rounded()))% of usual" } ?? "last night"
            result.append(RecoveryReading(label: "Sleep", value: String(format: "%d:%02d", minutes / 60, minutes % 60), unit: "",
                                          note: note, noteColor: KXColor.inkSecondary))
        } else {
            result.append(RecoveryReading(label: "Sleep", value: "–", unit: "",
                                          note: health.stoppedWaitingToday ? "not in yet" : missing, noteColor: KXColor.inkSecondary))
        }
        return result
    }

    /// Up to three readings (HRV, resting heart rate, sleep, then your score) from the
    /// recovery breakdown.
    static func readings(_ recovery: RecoveryScore) -> [RecoveryReading] {
        recovery.parts.compactMap(reading).prefix(3).map { $0 }
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private static func reading(_ part: RecoveryScore.Part) -> RecoveryReading? {
        let detail = part.detail
        switch part.name {
        case "HRV":
            guard let ms = firstInt("(\\d+) ms", in: detail) else { return nil }
            let percent = firstInt("(\\d+)% (?:above|below)", in: detail) ?? 0
            let up = detail.contains("% above")
            return RecoveryReading(label: "HRV", value: "\(ms)", unit: "ms",
                                   note: percent == 0 ? "Your usual" : "\(up ? "▲" : "▼") \(percent)% vs usual",
                                   noteColor: percent == 0 ? KXColor.inkSecondary : (up ? KXColor.success : KXColor.warning))
        case "Resting HR":
            guard let bpm = firstInt("(\\d+) bpm", in: detail) else { return nil }
            let delta = firstInt("(\\d+) (?:above|below)", in: detail) ?? 0
            let below = detail.contains("below")
            return RecoveryReading(label: "Resting HR", value: "\(bpm)", unit: "bpm",
                                   note: delta == 0 ? "Your usual" : "\(below ? "▼" : "▲") \(delta) bpm",
                                   noteColor: delta == 0 ? KXColor.inkSecondary : (below ? KXColor.success : KXColor.warning))
        case "Sleep":
            let asleep = detail.components(separatedBy: " asleep").first ?? detail
            let aim = detail.components(separatedBy: "aim ").dropFirst().first?.components(separatedBy: " (").first
            return RecoveryReading(label: "Sleep", value: asleep, unit: "",
                                   note: aim.map { "aim \($0)" } ?? "last night", noteColor: KXColor.inkSecondary)
        default:
            return RecoveryReading(label: part.name, value: "\(Int(part.score.rounded()))", unit: "",
                                   note: "check-in", noteColor: KXColor.inkSecondary)
        }
    }
}

/// Small shared formatting for the exertion card and its detail screen.
enum TodayFormat {
    /// Exertion as a whole number (0–100).
    static func one(_ value: Double) -> String { "\(Int(max(0, value).rounded()))" }

    static func status(strain: Double, target: StrainTarget) -> String {
        if strain > target.high { return "Above today's target" }
        if strain >= target.low { return "In today's target" }
        return "\(one(target.low - strain)) to go today"
    }

    /// "Good · ready to push" under the recovery score.
    static func headline(_ band: RecoveryScore.Band) -> String {
        switch band {
        case .low: return "Low · take it easier"
        case .fair: return "Fair · go steady"
        case .good: return "Good · ready to push"
        case .great: return "Great · ready to push"
        }
    }

    static func color(_ band: RecoveryScore.Band) -> Color {
        switch band {
        case .low: return KXColor.danger
        case .fair: return KXColor.warning
        case .good, .great: return KXColor.success
        }
    }

    static func legsLevel(_ status: LegsLoad.Status) -> KXStatusPill.Level {
        switch status {
        case .fresh: return .optimal
        case .ok: return .neutral
        case .tired: return .low
        }
    }
}

/// Everything behind today's numbers: the recovery breakdown, then exertion (why today's
/// target is what it is, what's counted so far, this week against your usual) and legs.
struct TodayBodyDetailView: View {
    let report: StrainReport
    var isWaitingForLastNight = false
    @Environment(\.dismiss) private var dismiss

    private var strain: Double { report.today.strain }
    private var target: StrainTarget { report.target }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        KXSectionHeader("Recovery")
                        if let recovery = report.recovery {
                            RecoveryBreakdownSection(recovery: recovery)
                        } else {
                            Text(isWaitingForLastNight
                                 ? "Waiting for last night's sleep from Apple Health. Pull down on Today to refresh."
                                 : "Add your score, or connect Apple Health, to see your recovery.")
                                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    exertion
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXSectionHeader("Legs", subtitle: report.legs.status.title)
                        Text(report.legs.status.advice)
                            .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(KXColor.accent)
    }

    private var exertion: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Exertion", subtitle: "\(TodayFormat.one(strain)) of 100 · target \(TodayFormat.one(target.low))–\(TodayFormat.one(target.high))")
            Text(TodayFormat.status(strain: strain, target: target) + ". " + target.reason)
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !report.today.activities.isEmpty { activities }
            WeekVsUsualBar(ratio: report.weekVsUsual)
        }
        .kxCard()
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            ForEach(report.today.activities) { activity in
                HStack {
                    Image(systemName: symbol(activity.source))
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(activity.name).font(KXFont.callout).foregroundStyle(KXColor.ink)
                    if activity.usedHeartRate {
                        Image(systemName: "heart.fill").font(KXFont.caption2).foregroundStyle(KXColor.danger)
                            .accessibilityLabel("from heart rate")
                    }
                    Spacer()
                    Text("+\(TodayFormat.one(Strain.strain(load: activity.load)))")
                        .font(KXFont.captionEmphasis.monospacedDigit())
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            Text("Exertion isn't additive: each point takes more than the last, so the day's total is less than the sum.")
                .font(KXFont.caption2)
                .foregroundStyle(KXColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func symbol(_ source: StrainActivity.Source) -> String {
        switch source {
        case .run: return "figure.run"
        case .lift: return "dumbbell"
        case .other: return "figure.mixed.cardio"
        case .steps: return "figure.walk"
        }
    }
}

/// A 0–100 ring: today's strain over a faint target band.
struct StrainRing: View {
    let strain: Double
    let target: StrainTarget
    var lineWidth: CGFloat = 12

    private func share(_ value: Double) -> Double { min(max(value / Strain.maximum, 0), 1) }

    var body: some View {
        ZStack {
            Circle().stroke(KXColor.border, lineWidth: lineWidth)
            Circle()
                .trim(from: share(target.low), to: share(target.high))
                .stroke(KXColor.accent.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: share(strain))
                .stroke(strain > target.high ? KXColor.warning : KXColor.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(TodayFormat.one(strain))
                    .font(KXFont.number(34))
                    .foregroundStyle(KXColor.ink)
                Text("of 100").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exertion \(TodayFormat.one(strain)) of 100")
        .accessibilityValue("Target \(TodayFormat.one(target.low)) to \(TodayFormat.one(target.high))")
    }
}

/// "This week: 112% of your usual" on a 0–200% bar with the normal range marked.
struct WeekVsUsualBar: View {
    let ratio: Double?

    private var normal: ClosedRange<Double> { LoadStatus.optimalRange }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack {
                Text("This week vs your usual").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                Spacer()
                Text(ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "After 2 weeks")
                    .font(KXFont.captionEmphasis.monospacedDigit())
                    .foregroundStyle(KXColor.ink)
            }
            GeometryReader { geo in
                let width = geo.size.width
                let x = { (value: Double) in width * min(max(value, 0), 2) / 2 }
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.border).frame(height: 8)
                    Rectangle().fill(KXColor.success.opacity(0.35))
                        .frame(width: x(normal.upperBound) - x(normal.lowerBound), height: 8)
                        .offset(x: x(normal.lowerBound))
                    if let ratio {
                        Capsule().fill(ratio > normal.upperBound ? KXColor.warning : KXColor.ink)
                            .frame(width: max(8, x(ratio)), height: 8)
                    }
                }
            }
            .frame(height: 8)
            Text(caption)
                .font(KXFont.caption2)
                .foregroundStyle(KXColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        guard let ratio else { return "Your last 7 days against an average week of the last 4, once there's two weeks of training." }
        if ratio > normal.upperBound { return "A big jump on your usual week. Keep an eye on recovery: if it drops, starting a session offers a lighter version." }
        if ratio < normal.lowerBound { return "Lighter than usual: fine for a recovery week." }
        return "Green is a normal week (\(Int(normal.lowerBound * 100))–\(Int(normal.upperBound * 100))% of your usual)."
    }
}

/// What makes up today's recovery: each reading, its score, its share and the points it adds.
struct RecoveryBreakdownSection: View {
    let recovery: RecoveryScore

    private var sorted: [RecoveryScore.Part] { recovery.parts.sorted { $0.share > $1.share } }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
                Text("\(Int(recovery.score))").font(KXFont.display).foregroundStyle(KXColor.ink)
                Text(recovery.band.title).font(KXFont.headline).foregroundStyle(KXColor.inkSecondary)
            }
            contributionBar
            ForEach(sorted, id: \.name) { part in
                row(part)
            }
            Text("Each reading is compared with your usual and scored 0–100: a normal day for you is about 72, better than usual 85+, and 90+ means clearly better on that reading. The total is the readings weighted HRV 45%, resting heart rate 25%, sleep 20% and your score 10%; a missing reading is left out and the others share its weight. \"Your usual\" is the middle of your last 30 days.")
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The total as segments, one per reading, sized by the points each adds.
    private var contributionBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(sorted, id: \.name) { part in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: part.name))
                        .frame(width: max(0, geo.size.width * part.points / 100 - 2))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.border, in: RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func row(_ part: RecoveryScore.Part) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Circle().fill(color(for: part.name)).frame(width: 10, height: 10).padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(part.detail).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                Text(part.rule).font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(part.score.rounded()))/100").font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                Text("+\(Int(part.points.rounded())) pts · \(Int((part.share * 100).rounded()))%")
                    .font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .padding(KXSpacing.md)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func color(for name: String) -> Color {
        switch name {
        case "HRV": return KXColor.accent
        case "Resting HR": return KXColor.lift
        case "Sleep": return KXColor.teal
        default: return KXColor.warning
        }
    }
}

// MARK: - Daily strain chart

/// Strain per day for the last week or month, with today's target marked.
struct DailyStrainChart: View {
    let days: [DayStrain]
    var target: StrainTarget?
    @State private var selected: Date?
    @AppStorage("dashboard.loadRange") private var range = 7

    private var shown: [DayStrain] { Array(days.suffix(range)) }
    private var isWeek: Bool { range == 7 }

    private var selectedDay: DayStrain? {
        guard let selected else { return nil }
        return shown.first { Calendar.kinetix.isDate($0.date, inSameDayAs: selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    KXOverline("Daily exertion")
                    Text(isWeek ? "Last 7 days" : "Last 30 days").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
                Picker("Period", selection: $range) {
                    Text("Week").tag(7)
                    Text("Month").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .accessibilityIdentifier("dashboard.loadRange")
            }
            Chart {
                if let target {
                    // Today's target as a shaded band behind the bars.
                    RectangleMark(yStart: .value("Low", target.low), yEnd: .value("High", target.high))
                        .foregroundStyle(KXColor.accent.opacity(0.1))
                }
                ForEach(shown) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Exertion", day.strain), width: .fixed(isWeek ? 26 : 7))
                        .foregroundStyle(barColor(day))
                        .cornerRadius(isWeek ? 6 : 3)
                }
                if let target {
                    ForEach([target.low, target.high], id: \.self) { value in
                        RuleMark(y: .value("Target", value))
                            .foregroundStyle(KXColor.accent.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                if let day = selectedDay {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(KXColor.inkTertiary)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(day)
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(KXColor.border)
                    AxisValueLabel().foregroundStyle(KXColor.inkSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: isWeek ? 1 : 7)) { _ in
                    AxisValueLabel(format: isWeek ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated), centered: true)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            .chartXScale(range: .plotDimension(startPadding: 2, endPadding: isWeek ? 2 : 14))
            .chartXSelection(value: $selected)
            .frame(height: 190)
            .accessibilityLabel("Daily exertion, last \(range) days")
            Text(target == nil ? "Touch and drag across the chart to see each day." : "The shaded band is today's target; amber days went over it. Touch and drag to see each day.")
                .font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
        }
        .kxCard()
    }

    /// Today in the accent colour, days over the target in amber, the rest in the run colour.
    private func barColor(_ day: DayStrain) -> Color {
        if Calendar.kinetix.isDateInToday(day.date) { return KXColor.accent }
        if let target, day.strain > target.high { return KXColor.warning }
        return KXColor.run
    }

    private func tooltip(_ day: DayStrain) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month())).font(KXFont.caption2Emphasis)
            Text("Exertion \(TodayFormat.one(day.strain))").font(KXFont.caption2Emphasis)
            ForEach(day.activities.prefix(4)) { activity in
                Text(activity.name).font(KXFont.caption2)
            }
        }
        .foregroundStyle(KXColor.ink)
        .padding(KXSpacing.sm)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
        .shadow(color: KXShadow.color, radius: 6, y: 2)
    }
}
