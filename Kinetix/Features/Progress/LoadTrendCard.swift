import SwiftUI
import Charts
import TrainingEngine

/// Acute:chronic ratio over the last 8 weeks against the undertrained / optimal / high zones.
struct LoadTrendCard: View {
    let report: LoadReport
    @State private var selected: Date?

    private struct Point: Identifiable {
        let date: Date
        let ratio: Double
        var id: Date { date }
    }

    private var points: [Point] {
        report.ratioTrend.compactMap { entry in entry.ratio.map { Point(date: entry.date, ratio: min($0, 2.2)) } }
    }

    private var selectedPoint: Point? {
        guard let selected else { return nil }
        return points.first { Calendar.kinetix.isDate($0.date, inSameDayAs: selected) }
    }

    private func band(top: CGFloat, bottom: CGFloat, plot: CGRect, color: Color, label: String) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: plot.width, height: max(0, bottom - top))
            .overlay(alignment: .topTrailing) {
                Text(label).font(.caption2).foregroundStyle(KXColor.inkSecondary).padding(4)
            }
            .offset(x: plot.minX, y: top)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Load ratio trend", subtitle: "Acute : chronic, last 8 weeks")
            if points.count < 2 {
                Text("Your ratio appears after about two weeks of training. Keep logging sessions.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Ratio", point.ratio))
                            .foregroundStyle(KXColor.ink)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let last = points.last {
                        PointMark(x: .value("Date", last.date), y: .value("Ratio", last.ratio))
                            .foregroundStyle(KXColor.ink)
                            .symbolSize(60)
                            .annotation(position: .top, alignment: .trailing) {
                                Text(String(format: "%.2f", last.ratio)).font(.caption.weight(.semibold)).foregroundStyle(KXColor.ink)
                            }
                    }
                    if let point = selectedPoint {
                        RuleMark(x: .value("Date", point.date))
                            .foregroundStyle(KXColor.inkTertiary)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(point.date.formatted(.dateTime.day().month())).font(.caption2.weight(.semibold))
                                    Text(String(format: "Ratio %.2f · %@", point.ratio, LoadStatus.from(ratio: point.ratio).title)).font(.caption2)
                                }
                                .foregroundStyle(KXColor.ink)
                                .padding(KXSpacing.sm)
                                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
                                .shadow(color: KXShadow.color, radius: 6, y: 2)
                            }
                    }
                }
                .chartYScale(domain: 0...2.2)
                .chartBackground { proxy in
                    // Zone bands (recessive washes) behind the line.
                    GeometryReader { geo in
                        if let plotAnchor = proxy.plotFrame {
                            let plot = geo[plotAnchor]
                            let y = { (value: Double) in plot.minY + (proxy.position(forY: value) ?? 0) }
                            ZStack(alignment: .topLeading) {
                                band(top: y(2.2), bottom: y(1.3), plot: plot, color: KXColor.danger.opacity(0.1), label: "High")
                                band(top: y(1.3), bottom: y(0.8), plot: plot, color: KXColor.success.opacity(0.14), label: "Optimal")
                                band(top: y(0.8), bottom: y(0), plot: plot, color: KXColor.warning.opacity(0.14), label: "Under")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 0.8, 1.3, 2.0]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(KXColor.border)
                        AxisValueLabel().foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .chartXSelection(value: $selected)
                .frame(height: 180)
                .accessibilityLabel("Load ratio over the last 8 weeks; latest \(String(format: "%.2f", points.last?.ratio ?? 0))")
            }
        }
        .kxCard()
    }
}
