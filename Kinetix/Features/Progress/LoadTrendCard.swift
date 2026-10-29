import SwiftUI
import Charts
import TrainingEngine

/// The last 7 days against an average week of the last 4 (as a % of usual), over 8 weeks,
/// against the lighter / normal / big-jump bands.
struct LoadTrendCard: View {
    let report: LoadReport
    @State private var selected: Date?

    private struct Point: Identifiable {
        let date: Date
        let ratio: Double
        var id: Date { date }
    }

    private var points: [Point] {
        report.ratioTrend.compactMap { entry in entry.ratio.map { Point(date: entry.date, ratio: min($0, 2.2) * 100) } }
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
                Text(label).font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary).padding(4)
            }
            .offset(x: plot.minX, y: top)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Week vs your usual", subtitle: "Last 7 days as a % of an average week, over 8 weeks")
            if points.count < 2 {
                Text("This appears after about two weeks of training. Keep logging sessions.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Percent", point.ratio))
                            .foregroundStyle(KXColor.ink)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let last = points.last {
                        PointMark(x: .value("Date", last.date), y: .value("Percent", last.ratio))
                            .foregroundStyle(KXColor.ink)
                            .symbolSize(60)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("\(Int(last.ratio.rounded()))%").font(KXFont.captionEmphasis).foregroundStyle(KXColor.ink)
                            }
                    }
                    if let point = selectedPoint {
                        RuleMark(x: .value("Date", point.date))
                            .foregroundStyle(KXColor.inkTertiary)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(point.date.formatted(.dateTime.day().month())).font(KXFont.caption2Emphasis)
                                    Text("\(Int(point.ratio.rounded()))% of usual").font(KXFont.caption2)
                                }
                                .foregroundStyle(KXColor.ink)
                                .padding(KXSpacing.sm)
                                .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.sm))
                                .shadow(color: KXShadow.color, radius: 6, y: 2)
                            }
                    }
                }
                .chartYScale(domain: 0...220)
                .chartBackground { proxy in
                    // Zone bands (recessive washes) behind the line.
                    GeometryReader { geo in
                        if let plotAnchor = proxy.plotFrame {
                            let plot = geo[plotAnchor]
                            let y = { (value: Double) in plot.minY + (proxy.position(forY: value) ?? 0) }
                            ZStack(alignment: .topLeading) {
                                band(top: y(220), bottom: y(130), plot: plot, color: KXColor.danger.opacity(0.1), label: "Big jump")
                                band(top: y(130), bottom: y(80), plot: plot, color: KXColor.success.opacity(0.14), label: "Normal")
                                band(top: y(80), bottom: y(0), plot: plot, color: KXColor.warning.opacity(0.14), label: "Lighter")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 80, 130, 200]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(KXColor.border)
                        AxisValueLabel().foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .chartXSelection(value: $selected)
                .frame(height: 180)
                .accessibilityLabel("This week against your usual over the last 8 weeks; latest \(Int(points.last?.ratio ?? 0)) percent")
            }
        }
        .kxCard()
    }
}
