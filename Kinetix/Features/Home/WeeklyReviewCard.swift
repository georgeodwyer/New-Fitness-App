import SwiftUI
import SwiftData
import TrainingEngine

/// Sunday evening to Monday: how the week went, and what next week holds.
struct WeeklyReviewData {
    var weekStart: Date
    var review: WeekReview
    var nextWeek: [PlannedSessionModel]
    var nextWeekStart: Date
    /// "Build week 3 · long run 16 km".
    var focus: String?
    var notes: [String]

    /// The review shows from Sunday 5 pm until the end of Monday.
    static func isReviewTime(_ now: Date = .now) -> Bool {
        let calendar = Calendar.kinetix
        let weekday = calendar.weekday(of: now)
        return (weekday == .sunday && calendar.component(.hour, from: now) >= 17) || weekday == .monday
    }

    /// The week to review: on Monday the one just finished, otherwise the current one.
    @MainActor
    static func make(in context: ModelContext, now: Date = .now) -> WeeklyReviewData? {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        var weekStart = calendar.startOfISOWeek(for: today)
        if calendar.weekday(of: now) == .monday { weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart }
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart),
              let nextEnd = calendar.date(byAdding: .day, value: 7, to: weekEnd) else { return nil }

        let plans = ((try? context.fetch(FetchDescriptor<TrainingPlanModel>())) ?? []).filter { $0.isActive && !$0.isSoftDeleted }
        let sessions = plans.first?.sessions.filter { !$0.isSoftDeleted } ?? []
        let thisWeek = sessions.filter { $0.date >= weekStart && $0.date < weekEnd }
        let nextWeek = sessions.filter { $0.date >= weekEnd && $0.date < nextEnd && $0.status != .skipped }.sorted { $0.date < $1.date }

        let runs = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
            .filter { $0.countsTowardsHistory && $0.startedAt >= weekStart && $0.startedAt < weekEnd }
        let allLifts = ((try? context.fetch(FetchDescriptor<StrengthLogModel>())) ?? []).filter { $0.isFinished && !$0.isSoftDeleted }
        let lifts = allLifts.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }

        // Load this week against the average of the four before.
        let allRuns = ((try? context.fetch(FetchDescriptor<RunLogModel>())) ?? [])
        let entries = DashboardService.loadEntries(runs: allRuns, lifts: allLifts, external: IntegrationSettings.shared.loadWorkouts)
        func load(from: Date, to: Date) -> Double { entries.filter { $0.date >= from && $0.date < to }.reduce(0) { $0 + $1.load } }
        let thisLoad = load(from: weekStart, to: weekEnd)
        let earlier = (1...4).compactMap { back -> Double? in
            guard let start = calendar.date(byAdding: .day, value: -7 * back, to: weekStart),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            return load(from: start, to: end)
        }.filter { $0 > 0 }
        let usual = earlier.isEmpty ? 0 : earlier.reduce(0, +) / Double(earlier.count)

        let records = ((try? context.fetch(FetchDescriptor<PersonalRecordModel>())) ?? [])
            .filter { !$0.isSoftDeleted && $0.achievedAt >= weekStart && $0.achievedAt < weekEnd }
        let recordKeys = Set(records.map(\.recordKey)).count
        let bests = recordKeys > 0 ? ["\(recordKeys) gym record\(recordKeys == 1 ? "" : "s")"] : []

        let review = WeekReview.make(
            planned: thisWeek.map { WeekReview.Session(discipline: $0.kind.discipline, status: $0.status,
                                                       plannedMeters: $0.estimatedDistanceMeters ?? 0) },
            runMeters: runs.reduce(0) { $0 + $1.distanceMeters }, runs: runs.count, lifts: lifts.count,
            loadRatio: usual > 0 ? thisLoad / usual : nil, newBests: bests)

        var focus: String?
        var notes: [String] = []
        if let plan = plans.first, let outline = plan.outline,
           let index = outline.weekIndex(containing: weekEnd, calendar: calendar) {
            let week = outline.weeks[index]
            var parts = [week.isRecoveryWeek ? "Easier week" : "\(week.phase.displayName) week \(week.weekInPhase + 1)"]
            if let long = nextWeek.filter({ $0.kind == .run(.long) }).compactMap(\.estimatedDistanceMeters).max() {
                let units = ((try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []).first?.units ?? .metric
                parts.append("long run " + DisplayFormat(units: units).distance(long, decimals: 0))
            }
            focus = parts.joined(separator: " · ")
            notes = plan.notes(forWeek: index)
        }
        return WeeklyReviewData(weekStart: weekStart, review: review, nextWeek: nextWeek, nextWeekStart: weekEnd,
                                focus: focus, notes: notes)
    }
}

struct WeeklyReviewCard: View {
    let data: WeeklyReviewData
    let units: UnitSystem
    var onOpen: ((PlannedSessionModel) -> Void)?

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                KXOverline("Your week", color: KXColor.accent)
                Text(data.review.headline).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: KXSpacing.lg) {
                if data.review.sessionsPlanned > 0 {
                    KXMetric(label: "Sessions", value: "\(data.review.sessionsDone)/\(data.review.sessionsPlanned)", size: .small)
                }
                KXMetric(label: "Run", value: format.distance(data.review.runMeters), size: .small)
                KXMetric(label: "Gym", value: "\(data.review.lifts)", size: .small)
                if let ratio = data.review.loadRatio {
                    KXMetric(label: "Load", value: "\(Int((ratio * 100).rounded()))", unit: "% usual", size: .small)
                }
                Spacer(minLength: 0)
            }
            if data.review.sessionsPlanned > 0 {
                ProgressView(value: min(data.review.completion, 1))
                    .tint(data.review.completion >= 0.75 ? KXColor.success : KXColor.warning)
                    .accessibilityLabel("\(data.review.sessionsDone) of \(data.review.sessionsPlanned) sessions done")
            }

            if !data.nextWeek.isEmpty {
                Divider().overlay(KXColor.border)
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        KXOverline("Next week")
                        Spacer()
                        if let focus = data.focus {
                            Text(focus).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                    ForEach(data.nextWeek) { session in
                        Button {
                            onOpen?(session)
                        } label: {
                            HStack(spacing: KXSpacing.sm) {
                                Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                                    .frame(width: 34, alignment: .leading)
                                Circle().fill(session.kind.tint).frame(width: 8, height: 8)
                                Text(session.title).font(KXFont.callout).foregroundStyle(KXColor.ink).lineLimit(1)
                                Spacer(minLength: KXSpacing.xs)
                                if let structure = session.runStructure, structure.segments.count > 1 {
                                    SessionStructureBar(structure: structure).frame(width: 70, height: 8)
                                } else {
                                    Text("\(Int(session.plannedDurationMinutes)) min")
                                        .font(KXFont.caption.monospacedDigit()).foregroundStyle(KXColor.inkSecondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(onOpen == nil)
                    }
                    ForEach(data.notes.prefix(2), id: \.self) { note in
                        Label(note, systemImage: "info.circle").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxCard()
        .accessibilityIdentifier("today.weeklyReview")
    }
}

/// The review on demand (from Plan), any day of the week.
struct WeeklyReviewSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let units: UnitSystem

    var body: some View {
        NavigationStack {
            ScrollView {
                if let data = WeeklyReviewData.make(in: context) {
                    WeeklyReviewCard(data: data, units: units).padding(KXSpacing.screenMargin)
                } else {
                    KXEmptyState(symbol: "calendar", title: "No plan yet", message: "Build a plan to see your week here.")
                        .padding(KXSpacing.screenMargin)
                }
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Week review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .tint(KXColor.accent)
    }
}
