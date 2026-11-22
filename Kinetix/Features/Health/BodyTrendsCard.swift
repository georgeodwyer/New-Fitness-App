import SwiftUI
import TrainingEngine

/// Body on Today: the readings behind recovery as rows with a 30-day sparkline, the latest
/// value and how it's moved. Tap for the full charts.
struct BodyTrendsCard: View {
    @State private var health = HealthService.shared
    @State private var showDetail = false

    private static let metrics: [HealthMetric] = [.hrv, .restingHeartRate, .sleep, .vo2Max]

    var body: some View {
        if !health.isConnected {
            BodyCard()
        } else {
            Button { showDetail = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        KXOverline("Body · 30 days")
                        Spacer()
                        Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.bottom, KXSpacing.xs)
                    ForEach(Array(Self.metrics.enumerated()), id: \.offset) { index, metric in
                        row(metric)
                        if index < Self.metrics.count - 1 { Divider().overlay(KXColor.border) }
                    }
                }
                .kxCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.body")
            .sheet(isPresented: $showDetail) {
                NavigationStack {
                    ScrollView { BodyCard().padding(KXSpacing.screenMargin) }
                        .background(KXColor.background.ignoresSafeArea())
                        .navigationTitle("Body")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetail = false } } }
                }
                .tint(KXColor.accent)
            }
        }
    }

    private func days(_ metric: HealthMetric) -> [HealthDay] {
        let since = Calendar.kinetix.date(byAdding: .day, value: -30, to: .now) ?? .now
        return (health.metricDays[metric] ?? []).filter { $0.date >= since }
    }

    private func row(_ metric: HealthMetric) -> some View {
        let values = days(metric).map(\.value)
        let change = Self.change(metric, values)
        return HStack(spacing: KXSpacing.sm) {
            Text(metric.displayName)
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkSecondary)
                .frame(width: 78, alignment: .leading)
            SparklineShape(values: values)
                .stroke(KXColor.run, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
                .frame(width: 110, height: 22)
                .opacity(values.count >= 2 ? 1 : 0)
            Text(values.last.map { Self.format(metric, $0) } ?? "–")
                .font(KXFont.number(18, relativeTo: .headline))
                .foregroundStyle(values.isEmpty ? KXColor.inkTertiary : KXColor.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(change.text)
                .font(KXFont.caption)
                .foregroundStyle(change.color)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, KXSpacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.displayName) \(values.last.map { Self.format(metric, $0) } ?? "no reading"), \(change.text)")
    }

    static func format(_ metric: HealthMetric, _ value: Double) -> String {
        switch metric {
        case .sleep:
            let minutes = Int((value * 60).rounded())
            return String(format: "%d:%02d", minutes / 60, minutes % 60)
        case .vo2Max: return String(format: "%.0f", value)
        default: return "\(Int(value.rounded()))"
        }
    }

    /// The last week's average against the first week's: HRV in %, the rest in units; sleep
    /// shows its average instead.
    static func change(_ metric: HealthMetric, _ values: [Double]) -> (text: String, color: Color) {
        guard values.count >= 8 else { return ("", KXColor.inkSecondary) }
        let first = values.prefix(7).reduce(0, +) / Double(min(7, values.count))
        let last = values.suffix(7).reduce(0, +) / Double(min(7, values.count))
        switch metric {
        case .sleep:
            return ("avg", KXColor.inkSecondary)
        case .hrv:
            guard first > 0 else { return ("", KXColor.inkSecondary) }
            let percent = Int(((last / first - 1) * 100).rounded())
            return (percent == 0 ? "–" : "\(percent > 0 ? "+" : "−")\(abs(percent))%", percent > 0 ? KXColor.success : percent < 0 ? KXColor.warning : KXColor.inkSecondary)
        default:
            let delta = Int((last - first).rounded())
            let good = metric == .restingHeartRate ? delta < 0 : delta > 0
            return (delta == 0 ? "–" : "\(delta > 0 ? "+" : "−")\(abs(delta))", delta == 0 ? KXColor.inkSecondary : (good ? KXColor.success : KXColor.warning))
        }
    }
}

/// A plain line through the values, scaled to the frame.
struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return path }
        let span = max(high - low, 0.0001)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                                y: rect.maxY - rect.height * CGFloat((value - low) / span))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
