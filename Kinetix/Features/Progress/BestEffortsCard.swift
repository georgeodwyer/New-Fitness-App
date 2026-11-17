import SwiftUI
import SwiftData
import TrainingEngine

/// Fastest time over each distance (1 km, 5K, 10K…) from any GPS run, each opening its run.
/// On Progress → Running and on the Profile tab.
struct BestEffortsCard: View {
    let units: UnitSystem
    @Query(filter: #Predicate<RunLogModel> { $0.isFinished && $0.deletedAt == nil }, sort: \RunLogModel.startedAt, order: .reverse)
    private var runs: [RunLogModel]
    @State private var bests: [Row] = []

    struct Row: Identifiable, Equatable {
        let distance: BestEffortDistance
        let seconds: Double
        let runId: UUID
        let date: Date
        var id: Double { distance.meters }
    }

    private var format: DisplayFormat { DisplayFormat(units: units) }
    private var counted: [RunLogModel] { runs.filter(\.countsTowardsHistory) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Best efforts", subtitle: "Your fastest time over each distance, from any run")
            if bests.isEmpty {
                KXEmptyState(symbol: "stopwatch", title: "No best efforts yet",
                             message: "Run at least 1 km with GPS and your fastest times show up here.")
            }
            ForEach(bests) { row in
                NavigationLink {
                    if let run = runs.first(where: { $0.id == row.runId }) { RunDetailView(log: run, units: units) }
                } label: {
                    HStack {
                        Image(systemName: "medal.fill").foregroundStyle(KXColor.warning).accessibilityHidden(true)
                        Text(row.distance.displayName).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Units.formatMinutesSeconds(row.seconds)).font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
                            Text("\(format.pace(Pace(secondsPerKm: row.seconds / row.distance.meters * 1000))) · \(row.date.formatted(.dateTime.day().month().year()))")
                                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                        Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
        .task(id: counted.count) { bests = computeBests() }
    }

    private func computeBests() -> [Row] {
        var best: [BestEffortDistance: Row] = [:]
        // Strava's summary map has no timestamps, so imported runs can't give best efforts.
        for run in counted where run.distanceMeters >= BestEffortDistance.oneKilometre.meters && !run.isImportedFromStrava {
            for (distance, seconds) in RunAnalysis.bestEfforts(route: run.route)
            where best[distance].map({ seconds < $0.seconds }) ?? true {
                best[distance] = Row(distance: distance, seconds: seconds, runId: run.id, date: run.startedAt)
            }
        }
        return BestEffortDistance.allCases.compactMap { best[$0] }
    }
}
