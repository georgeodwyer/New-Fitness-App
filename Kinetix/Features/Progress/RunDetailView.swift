import SwiftUI
import SwiftData
import Charts
import TrainingEngine

/// A finished run: route, totals, pace and heart-rate charts, splits, efforts against
/// target, planned vs actual, and where it was sent. Can be renamed, re-rated or deleted.
struct RunDetailView: View {
    let log: RunLogModel
    let units: UnitSystem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var sharing = false

    private var format: DisplayFormat { DisplayFormat(units: units) }
    private var route: [RoutePoint] { log.route }
    private var planned: PlannedSessionModel? {
        guard let id = log.plannedSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                header
                totals
                let pace = log.isImportedFromStrava ? [] : RunAnalysis.paceSeries(route: route)
                if pace.count >= 3 { RunLineChart(title: "Pace", points: pace, kind: .pace(units)) }
                let heartRate = RunAnalysis.heartRateSeries(log.heartRateSamples)
                if heartRate.count >= 3 { RunLineChart(title: "Heart rate", points: heartRate, kind: .heartRate) }
                if log.heartRateSamples.count >= 3 { HeartRateZonesCard(samples: log.heartRateSamples) }
                if !log.splits.isEmpty { splitsCard }
                if !log.laps.isEmpty { LapsCard(laps: log.laps, format: format) }
                if !log.segmentResults.isEmpty { PlannedVsActualCard(results: log.segmentResults, format: format) }
                if let planned { plannedCard(planned) }
                destinationsCard
                SaveAsTemplateButton(source: .run(log))
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete run", systemImage: "trash")
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
                .accessibilityIdentifier("run.delete")
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle(log.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
                .accessibilityIdentifier("run.share")
            Button("Edit") { editing = true }.accessibilityIdentifier("run.edit")
        }
        .sheet(isPresented: $sharing) { ShareSessionView(source: .run(log), units: units) }
        .sheet(isPresented: $editing) {
            EditSessionSheet(title: log.title, effort: log.effort, kind: "run") { title, effort in
                RunService.update(log, title: title, effort: effort, in: context)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Delete this run?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete run", role: .destructive) {
                RunService.delete(log, in: context)
                dismiss()
            }
        } message: {
            Text("It's removed from Kinetix and your training load\(planned != nil ? ", and the planned session is reopened" : ""). Copies in Apple Health or on Strava aren't affected.")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack(spacing: KXSpacing.xs) {
                KXOverline(log.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()), color: KXColor.accent)
                Spacer()
                if let tag = log.sourceTag { KXChip(text: tag, variant: .outlined) }
                if log.usedSimulatedGPS { KXChip(text: "Simulated", systemImage: "location.slash", variant: .outlined) }
            }
            Text(log.title.isEmpty ? "Run" : log.title).font(KXFont.display).foregroundStyle(KXColor.ink)
        }
    }

    private var totals: some View {
        var secondary: [RunStatsGrid.Stat] = [
            .init(label: "Max HR", value: log.maxHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm"),
            .init(label: "Effort", value: "\(Int(log.effort))", unit: "/10"),
            .init(label: "Load", value: "\(Int(log.load.rounded()))"),
        ]
        if log.targetedSeconds > 0 {
            secondary.append(.init(label: "On target", value: "\(Int((log.timeInTargetSeconds / log.targetedSeconds * 100).rounded()))", unit: "%"))
        }
        return RunHeroCard(
            showsMap: route.count > 1,
            stats: [
                .init(label: "Distance", value: Units.formatDistance(meters: log.distanceMeters, units: units), unit: Units.distanceUnitLabel(units)),
                .init(label: "Avg pace", value: log.averagePace.map { Units.formatPace($0, units: units) } ?? "--:--", unit: Units.paceUnitLabel(units)),
                .init(label: "Time", value: Units.formatMinutesSeconds(log.durationSeconds)),
                .init(label: "Avg HR", value: log.averageHeartRate.map { "\(Int($0))" } ?? "--"),
            ],
            secondary: secondary
        ) {
            RouteMap(route: route)
        }
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Splits", subtitle: units == .metric ? "Per kilometre" : "Per mile")
            let fastest = log.splits.map(\.durationSeconds).min() ?? 0
            let slowest = log.splits.map(\.durationSeconds).max() ?? 1
            ForEach(log.splits, id: \.index) { split in
                HStack(spacing: KXSpacing.md) {
                    Text("\(split.index)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 24, alignment: .leading)
                    GeometryReader { geo in
                        // Faster splits draw longer bars.
                        let range = max(slowest - fastest, 1)
                        let fraction = 0.35 + 0.65 * (slowest - split.durationSeconds) / range
                        Capsule().fill(KXColor.run)
                            .frame(width: geo.size.width * fraction, height: 10)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 20)
                    .accessibilityHidden(true)
                    Text(Units.formatMinutesSeconds(split.durationSeconds))
                        .font(KXFont.bodyEmphasis.monospacedDigit()).frame(width: 56, alignment: .trailing)
                    Text(split.averageHeartRate.map { "\(Int($0))" } ?? "")
                        .font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary).frame(width: 32, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Split \(split.index), \(Units.formatMinutesSeconds(split.durationSeconds))"
                                    + (split.averageHeartRate.map { ", \(Int($0)) beats per minute" } ?? ""))
            }
        }
        .kxCard()
    }

    private func plannedCard(_ planned: PlannedSessionModel) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Planned vs actual", subtitle: planned.title)
            comparisonRow("Distance",
                          planned: planned.estimatedDistanceMeters.map { format.distance($0) } ?? "–",
                          actual: format.distance(log.distanceMeters))
            comparisonRow("Time", planned: "\(Int(planned.plannedDurationMinutes)) min",
                          actual: Units.formatMinutesSeconds(log.durationSeconds))
            comparisonRow("Effort", planned: "\(Int(planned.plannedEffort))/10", actual: "\(Int(log.effort))/10")
            if log.recordTypeRaw != nil {
                Text("Recorded from the Record tab and counted as this planned session.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .kxCard()
    }

    private func comparisonRow(_ label: String, planned: String, actual: String) -> some View {
        HStack {
            Text(label).font(KXFont.callout).foregroundStyle(KXColor.inkSecondary).frame(width: 70, alignment: .leading)
            Text(planned).font(KXFont.callout.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
            Image(systemName: "arrow.right").font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
            Text(actual).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): planned \(planned), actual \(actual)")
    }

    private var destinationsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            if log.isImportedFromStrava {
                Text("Recorded in another app and imported from Strava. Effort is estimated from heart rate; tap Edit to set it.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                StravaAttribution()
            } else {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                    Spacer()
                    Text(log.healthKitWorkoutId != nil ? "Saved" : "Not saved").foregroundStyle(KXColor.inkSecondary)
                }
            }
            HStack {
                Label("Strava", systemImage: "arrow.up.forward.app")
                Spacer()
                if let id = log.stravaActivityId, let url = URL(string: "https://www.strava.com/activities/\(id)") {
                    Link(destination: url) {
                        Text("View on Strava").font(KXFont.bodyEmphasis).foregroundStyle(StravaView.brand)
                    }
                } else {
                    Text("Not uploaded").foregroundStyle(KXColor.inkSecondary)
                }
            }
        }
        .font(KXFont.callout)
        .kxCard()
    }
}

/// Pace or heart rate across a run, with a crosshair and value on touch.
struct RunLineChart: View {
    enum Kind {
        case pace(UnitSystem)
        case heartRate
    }

    let title: String
    let points: [RunChartPoint]
    let kind: Kind
    @State private var selectedMinute: Double?

    private var color: Color {
        switch kind {
        case .pace: return KXColor.run
        case .heartRate: return KXColor.ink
        }
    }

    private func display(_ value: Double) -> String {
        switch kind {
        case .pace(let units): return Units.formatPace(Pace(secondsPerKm: value), units: units) + Units.paceUnitLabel(units)
        case .heartRate: return "\(Int(value.rounded())) bpm"
        }
    }

    private var selected: RunChartPoint? {
        guard let selectedMinute else { return nil }
        return points.min { abs($0.elapsed / 60 - selectedMinute) < abs($1.elapsed / 60 - selectedMinute) }
    }

    private var isPace: Bool { if case .pace = kind { return true } else { return false } }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                KXSectionHeader(title, subtitle: isPace ? "Higher is faster" : nil)
                Spacer()
                if let selected {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(display(selected.value)).font(KXFont.bodyEmphasis.monospacedDigit())
                        Text("at \(Units.formatMinutesSeconds(selected.elapsed))").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Minutes", point.elapsed / 60), y: .value(title, point.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let selected {
                    RuleMark(x: .value("Minutes", selected.elapsed / 60))
                        .foregroundStyle(KXColor.inkTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Minutes", selected.elapsed / 60), y: .value(title, selected.value))
                        .foregroundStyle(color)
                        .symbolSize(80)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: isPace))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(KXColor.border)
                    AxisValueLabel { if let minute = value.as(Double.self) { Text("\(Int(minute)) min") } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(KXColor.border)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(isPace ? display(number).replacingOccurrences(of: "/km", with: "").replacingOccurrences(of: "/mi", with: "")
                                        : "\(Int(number))")
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedMinute)
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
        .kxCard()
    }

    private var accessibilitySummary: String {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return title }
        if isPace { return "\(title) chart, from \(display(high)) to \(display(low))" }
        return "\(title) chart, from \(display(low)) to \(display(high))"
    }
}

/// Rename a session and change its effort.
struct EditSessionSheet: View {
    let kind: String
    let onSave: (String, Double) -> Void
    @State private var title: String
    @State private var effort: Double
    @Environment(\.dismiss) private var dismiss

    init(title: String, effort: Double, kind: String, onSave: @escaping (String, Double) -> Void) {
        _title = State(initialValue: title)
        _effort = State(initialValue: min(max(effort.rounded(), 1), 10))
        self.kind = kind
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $title)
                }
                Section {
                    Stepper(value: $effort, in: 1...10, step: 1) {
                        HStack {
                            Text("Effort")
                            Spacer()
                            KXEditableNumber(display: "\(Int(effort))", allowsDecimal: false, accessibilityLabel: "Effort") { typed in
                                effort = min(max(typed, 1), 10)
                            }
                            Text("/10").font(KXFont.bodyEmphasis)
                        }
                    }
                } footer: {
                    Text("Effort × minutes is this \(kind)'s training load, so changing it updates your load figures.")
                }
            }
            .navigationTitle("Edit \(kind)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(title, effort); dismiss() }
                }
            }
        }
        .tint(KXColor.accent)
    }
}
