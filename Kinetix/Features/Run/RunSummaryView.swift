import SwiftUI
import TrainingEngine

/// After a run: map, totals, time in target pace, heart rate, splits and segment results.
struct RunSummaryView: View {
    let title: String
    let summary: RunSummary
    let units: UnitSystem
    var simulated = false
    /// The saved run, to show its Strava upload as it happens.
    var log: RunLogModel? = nil
    let onDone: () -> Void
    @State private var strava = StravaService.shared
    @State private var sharing = false
    @State private var integrations = IntegrationSettings.shared

    private var format: DisplayFormat { DisplayFormat(units: units) }

    /// "View on Strava" once uploaded (Strava's required wording and colour), or progress.
    @ViewBuilder private var stravaStatus: some View {
        if let id = log?.stravaActivityId, let url = URL(string: "https://www.strava.com/activities/\(id)") {
            Link(destination: url) {
                Text("View on Strava").font(KXFont.bodyEmphasis).foregroundStyle(StravaView.brand)
            }
        } else if !simulated, strava.isConnected, integrations.stravaUploadRuns, log?.isFinished == true {
            HStack(spacing: KXSpacing.sm) {
                ProgressView()
                Text("Uploading to Strava…").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(simulated ? "Run complete · simulated GPS" : "Run complete", color: KXColor.success)
                    Text(title).font(KXFont.display).foregroundStyle(KXColor.ink)
                }
                stravaStatus
                totals
                if let log, log.isFinished, !simulated { PaceUpdateCard(log: log) }
                if !summary.segments.isEmpty { PlannedVsActualCard(results: summary.segments, format: format) }
                targetCard
                if summary.heartRateSamples.count >= 3 { HeartRateZonesCard(samples: summary.heartRateSamples) }
                if !summary.splits.isEmpty { splitsCard }
                if let laps = summary.laps, !laps.isEmpty { LapsCard(laps: laps, format: format) }
                if let log, log.isFinished { SaveAsTemplateButton(source: .run(log)) }
            }
            .padding(KXSpacing.screenMargin)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: KXSpacing.sm) {
                if let log, log.isFinished {
                    Button { sharing = true } label: { Label("Share run", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                        .accessibilityIdentifier("summary.share")
                }
                Button("Done", action: onDone)
                    .buttonStyle(.kx(.primary, fullWidth: true))
            }
            .padding(KXSpacing.screenMargin)
                .background(KXColor.background)
        }
        .background(KXColor.background.ignoresSafeArea())
        .sheet(isPresented: $sharing) {
            if let log { ShareSessionView(source: .run(log), units: units) }
        }
    }

    private var totals: some View {
        RunHeroCard(
            showsMap: summary.route.count > 1,
            stats: [
                .init(label: "Distance", value: Units.formatDistance(meters: summary.distanceMeters, units: units), unit: Units.distanceUnitLabel(units)),
                .init(label: "Avg pace", value: summary.averagePace.map { Units.formatPace($0, units: units) } ?? "--:--", unit: Units.paceUnitLabel(units)),
                .init(label: "Time", value: Units.formatMinutesSeconds(summary.durationSeconds)),
                .init(label: "Avg HR", value: summary.averageHeartRate.map { "\(Int($0))" } ?? "--"),
            ],
            secondary: [
                .init(label: "Max HR", value: summary.maxHeartRate.map { "\(Int($0))" } ?? "--", unit: "bpm"),
                .init(label: "Splits", value: "\(summary.splits.count)"),
            ],
            footnote: summary.averageHeartRate == nil ? "Heart rate appears here once Apple Watch or a chest strap is connected." : nil
        ) {
            RouteMap(route: summary.route)
        }
    }

    private var targetCard: some View {
        HStack(spacing: KXSpacing.lg) {
            KXRingGauge(value: summary.timeInTargetFraction ?? 0,
                        label: summary.timeInTargetFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "--",
                        caption: "on target", tint: KXColor.success)
                .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text("Time in target pace").font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text(summary.targetedSeconds > 0
                     ? "\(Units.formatMinutesSeconds(summary.timeInTargetSeconds)) of \(Units.formatMinutesSeconds(summary.targetedSeconds)) in your target range (main efforts, not warm-up or recoveries)."
                     : "No paced efforts were measured on this run.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .kxCard()
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Splits", subtitle: units == .metric ? "Per kilometre" : "Per mile")
            let fastest = summary.splits.map(\.durationSeconds).min() ?? 0
            let slowest = summary.splits.map(\.durationSeconds).max() ?? 1
            ForEach(summary.splits, id: \.index) { split in
                HStack(spacing: KXSpacing.md) {
                    Text("\(split.index)").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary).frame(width: 24, alignment: .leading)
                    GeometryReader { geo in
                        // Faster splits draw longer bars.
                        let range = max(slowest - fastest, 1)
                        let fraction = 0.35 + 0.65 * (slowest - split.durationSeconds) / range
                        Capsule().fill(KXColor.accent.opacity(0.85))
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
                .accessibilityLabel("Split \(split.index), \(Units.formatMinutesSeconds(split.durationSeconds))")
            }
        }
        .kxCard()
    }
}
