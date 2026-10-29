import SwiftUI
import TrainingEngine

/// Top of the Plan tab: days to race (or where you are in the block), the predicted race time,
/// and the plan's phases as one timeline with a marker for this week. Tap for every phase.
struct RaceCountdownCard: View {
    let outline: PlanOutline
    let profile: AthleteProfile?

    @State private var showPhases = false
    private var calendar: Calendar { .kinetix }
    private var currentIndex: Int? { outline.weekIndex(containing: .now, calendar: calendar) }

    private var daysToRace: Int? {
        guard let event = outline.eventDate else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: event)).day
    }

    /// The race at the end of the goal, if it has one.
    private var raceMeters: Double? {
        switch profile?.goal {
        case .first5k?, .faster5k?: return 5000
        case .faster10k?: return 10000
        case .halfMarathon?: return 21097.5
        case .marathon?: return 42195
        default: return nil
        }
    }

    var body: some View {
        Button { showPhases = true } label: {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let event = outline.eventDate, let days = daysToRace {
                            KXOverline("Race day · " + event.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                                Text("\(max(days, 0))")
                                    .font(KXFont.number(56, relativeTo: .largeTitle))
                                    .foregroundStyle(KXColor.ink)
                                Text(days > 0 ? (days == 1 ? "day to go" : "days to go") : "Race day")
                                    .font(KXFont.bodyEmphasis)
                                    .foregroundStyle(KXColor.inkSecondary)
                            }
                        } else if let index = currentIndex {
                            KXOverline("Your block")
                            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                                Text("Week \(index + 1)")
                                    .font(KXFont.number(44, relativeTo: .largeTitle))
                                    .foregroundStyle(KXColor.ink)
                                Text("of \(outline.weeks.count)")
                                    .font(KXFont.bodyEmphasis)
                                    .foregroundStyle(KXColor.inkSecondary)
                            }
                        } else {
                            KXOverline("Your block")
                            Text("Starts \(outline.weeks.first?.startDate.formatted(.dateTime.weekday(.wide).day().month()) ?? "soon")")
                                .font(KXFont.headline)
                                .foregroundStyle(KXColor.ink)
                        }
                    }
                    Spacer(minLength: KXSpacing.sm)
                    if let meters = raceMeters, let profile {
                        VStack(alignment: .trailing, spacing: 2) {
                            KXOverline("Predicted")
                            Text(Units.formatMinutesSeconds(PaceZones(vdot: FormService.predictionVDOT(for: profile)).predictedTime(distanceMeters: meters)))
                                .font(KXFont.number(26, relativeTo: .title2))
                                .foregroundStyle(KXColor.ink)
                            Text("from your current fitness")
                                .font(KXFont.caption)
                                .foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                }
                PhaseTimeline(outline: outline, currentIndex: currentIndex)
                if let index = currentIndex {
                    let week = outline.weeks[index]
                    Text("Week \(index + 1) of \(outline.weeks.count) · \(week.phase.displayName)\(week.isRecoveryWeek ? " · easier week" : ""): \(week.phase.explanation)")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .kxCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every phase of your plan")
        .accessibilityIdentifier("plan.countdown")
        .sheet(isPresented: $showPhases) { PlanPhasesView(outline: outline) }
    }
}

/// The plan's phases side by side (as wide as their weeks), labelled, with a marker for this week.
struct PhaseTimeline: View {
    let outline: PlanOutline
    let currentIndex: Int?

    private struct Segment: Identifiable {
        let phase: TrainingPhase
        let weeks: Int
        let first: Int
        var id: Int { first }
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        for (index, week) in outline.weeks.enumerated() {
            if let last = result.last, last.phase == week.phase {
                result[result.count - 1] = Segment(phase: last.phase, weeks: last.weeks + 1, first: last.first)
            } else {
                result.append(Segment(phase: week.phase, weeks: 1, first: index))
            }
        }
        return result
    }

    var body: some View {
        let total = max(outline.weeks.count, 1)
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = geo.size.width - gap * CGFloat(max(segments.count - 1, 0))
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(segments) { segment in
                            let isCurrent = currentIndex.map { $0 >= segment.first && $0 < segment.first + segment.weeks } ?? false
                            Capsule()
                                .fill(KXColor.phase(TrainingPhase.allCases.firstIndex(of: segment.phase) ?? 0))
                                .opacity(isCurrent ? 1 : 0.4)
                                .frame(width: usable * CGFloat(segment.weeks) / CGFloat(total))
                        }
                    }
                    if let currentIndex {
                        Capsule()
                            .fill(KXColor.ink)
                            .frame(width: 3, height: 16)
                            .offset(x: geo.size.width * (CGFloat(currentIndex) + 0.5) / CGFloat(total) - 1.5)
                    }
                }
                .frame(height: geo.size.height)
            }
            .frame(height: 16)
            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = geo.size.width - gap * CGFloat(max(segments.count - 1, 0))
                HStack(spacing: gap) {
                    ForEach(segments) { segment in
                        let isCurrent = currentIndex.map { $0 >= segment.first && $0 < segment.first + segment.weeks } ?? false
                        Text(segment.phase.displayName)
                            .font(isCurrent ? KXFont.captionEmphasis : KXFont.caption)
                            .foregroundStyle(isCurrent ? KXColor.ink : KXColor.inkTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: usable * CGFloat(segment.weeks) / CGFloat(total), alignment: .leading)
                    }
                }
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phases: " + segments.map { "\($0.phase.displayName), \($0.weeks) week\($0.weeks == 1 ? "" : "s")" }.joined(separator: ", "))
    }
}

/// Planned running per week for the whole plan, with what was run in the weeks so far.
struct WeeklyDistanceCard: View {
    let outline: PlanOutline
    let runs: [RunLogModel]
    let format: DisplayFormat
    /// The plan's sessions: weeks already built show what's actually planned, not the target.
    var sessions: [PlannedSessionModel] = []

    /// Each week's planned running: the sessions when they're built, else the outline's target.
    private var plannedMeters: [Double] {
        outline.weeks.map { week in
            let end = calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? week.startDate
            let inWeek = sessions.filter { !$0.isSoftDeleted && $0.date >= week.startDate && $0.date < end }
            return inWeek.isEmpty ? week.runVolumeMeters : PlannedSessionModel.plannedRunMeters(inWeek)
        }
    }

    private var calendar: Calendar { .kinetix }
    private var currentIndex: Int? { outline.weekIndex(containing: .now, calendar: calendar) }

    /// Metres run in each week up to this one (nil for weeks still ahead).
    private var doneMeters: [Int: Double] {
        var result: [Int: Double] = [:]
        let today = Date.now
        for (index, week) in outline.weeks.enumerated() where week.startDate <= today {
            let end = calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? week.startDate
            result[index] = runs.filter { !$0.usedSimulatedGPS && $0.startedAt >= week.startDate && $0.startedAt < end }
                .reduce(0) { $0 + $1.distanceMeters }
        }
        return result
    }

    var body: some View {
        let done = doneMeters
        let planned = plannedMeters
        let top = max(planned.max() ?? 0, done.values.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                KXOverline("Weekly distance")
                Spacer()
                if let index = currentIndex {
                    Text("\(format.distance(done[index] ?? 0, decimals: 0)) of \(format.distance(planned[index], decimals: 0)) this week")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            GeometryReader { geo in
                let count = max(planned.count, 1)
                let gap: CGFloat = count > 16 ? 2 : 4
                let width = (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(planned.indices, id: \.self) { index in
                        let isCurrent = index == currentIndex
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: min(5, width / 3), style: .continuous)
                                .strokeBorder(isCurrent ? KXColor.accent : KXColor.border, lineWidth: isCurrent ? 2 : 1.5)
                                .frame(height: max(4, geo.size.height * planned[index] / top))
                            if let meters = done[index], meters > 0 {
                                RoundedRectangle(cornerRadius: min(5, width / 3), style: .continuous)
                                    .fill(KXColor.run)
                                    .frame(height: max(3, geo.size.height * meters / top))
                            }
                        }
                        .frame(width: width)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 92)
            HStack(spacing: KXSpacing.md) {
                legend(KXColor.run, filled: true, "Run")
                legend(KXColor.border, filled: false, "Planned")
                if currentIndex != nil { legend(KXColor.accent, filled: false, "This week") }
                Spacer()
                Text("Week 1–\(planned.count)").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
        }
        .kxCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly distance")
        .accessibilityValue(currentIndex.map { "This week \(format.distance(done[$0] ?? 0, decimals: 0)) of \(format.distance(plannedMeters[$0], decimals: 0)) planned" } ?? "")
    }

    private func legend(_ color: Color, filled: Bool, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(filled ? color : .clear)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(filled ? .clear : color, lineWidth: 1.5))
                .frame(width: 10, height: 10)
            Text(text).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }
}
