import SwiftUI
import SwiftData
import TrainingEngine

// MARK: - This week vs plan

struct WeekProgressCard: View {
    let data: DashboardData
    let units: UnitSystem

    private var format: DisplayFormat { DisplayFormat(units: units) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            KXSectionHeader("This week", subtitle: "Done so far against your plan")
            KXMeter(
                label: "Running distance",
                valueText: format.distance(data.actualRunMeters),
                targetText: format.distance(data.plannedRunMeters, decimals: 0),
                fraction: data.plannedRunMeters > 0 ? data.actualRunMeters / data.plannedRunMeters : 0,
                color: KXColor.run
            )
            KXMeter(
                label: "Lifting volume",
                valueText: compactWeight(data.actualLiftVolumeKg),
                targetText: compactWeight(data.plannedLiftVolumeKg),
                fraction: data.plannedLiftVolumeKg > 0 ? data.actualLiftVolumeKg / data.plannedLiftVolumeKg : 0,
                color: KXColor.lift
            )
            Divider()
            adherence
        }
        .kxCard()
    }

    private func compactWeight(_ kg: Double) -> String { DisplayFormat(units: units).volume(kg) }

    private var adherence: some View {
        let a = data.adherence
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plan adherence").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                Spacer()
                Text(a.percent.map { "\($0)%" } ?? "–").font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
            }
            // Part-to-whole: done / skipped / missed / still to come, with 2 pt gaps.
            GeometryReader { geo in
                let total = max(a.total, 1)
                let parts: [(Int, Color)] = [(a.completed, KXColor.success), (a.skipped, KXColor.inkTertiary),
                                             (a.missed, KXColor.warning), (a.upcoming, KXColor.border)]
                let visible = parts.filter { $0.0 > 0 }
                let gaps = CGFloat(max(visible.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, part in
                        Rectangle().fill(part.1)
                            .frame(width: max(4, (geo.size.width - gaps) * CGFloat(part.0) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            HStack(spacing: KXSpacing.md) {
                legend("checkmark.circle.fill", KXColor.success, "\(a.completed) done")
                legend("arrow.left.arrow.right.circle.fill", KXColor.accent, "\(a.swapped) swapped")
                legend("xmark.circle.fill", KXColor.inkTertiary, "\(a.skipped) skipped")
                if a.missed > 0 { legend("exclamationmark.circle.fill", KXColor.warning, "\(a.missed) missed") }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func legend(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color).font(.caption)
            Text(text).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }
}

// MARK: - Week at a glance

struct WeekStripCard: View {
    let days: [DashboardData.WeekDay]

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Week at a glance")
            HStack(alignment: .top, spacing: KXSpacing.xs) {
                ForEach(days) { day in dayColumn(day) }
            }
            HStack(spacing: KXSpacing.lg) {
                key(KXColor.run, "Run")
                key(KXColor.lift, "Lift")
                key(KXColor.other, "Other")
                Spacer()
            }
        }
        .kxCard()
    }

    private func dayColumn(_ day: DashboardData.WeekDay) -> some View {
        VStack(spacing: KXSpacing.xs) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(KXFont.captionEmphasis)
                .foregroundStyle(day.isToday ? KXColor.accent : KXColor.inkSecondary)
            Text(day.date.formatted(.dateTime.day()))
                .font(KXFont.bodyEmphasis)
                .foregroundStyle(day.isToday ? KXColor.onAccent : KXColor.ink)
                .frame(width: 32, height: 32)
                .background(day.isToday ? KXColor.accent : .clear, in: Circle())
            VStack(spacing: 4) {
                if day.sessions.isEmpty {
                    Image(systemName: "moon.zzz")
                        .font(.caption2)
                        .foregroundStyle(KXColor.inkTertiary)
                        .frame(height: 26)
                } else {
                    ForEach(day.sessions) { session in sessionPip(session) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(day))
    }

    private func sessionPip(_ session: PlannedSessionModel) -> some View {
        ZStack {
            Circle()
                .fill(session.status == .skipped ? KXColor.surfaceTint : session.kind.tint)
                .frame(width: 26, height: 26)
            Image(systemName: statusSymbol(session))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(session.status == .skipped ? KXColor.inkTertiary : .white)
        }
    }

    private func statusSymbol(_ session: PlannedSessionModel) -> String {
        switch session.status {
        case .completed: return "checkmark"
        case .skipped: return "xmark"
        case .swapped: return "arrow.left.arrow.right"
        case .planned:
            switch session.kind.discipline {
            case .run: return "figure.run"
            case .strength: return "dumbbell.fill"
            case .crossTraining: return "bicycle"
            case .mobility: return "figure.flexibility"
            }
        }
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
    }

    private func accessibilityText(_ day: DashboardData.WeekDay) -> String {
        let name = day.date.formatted(.dateTime.weekday(.wide))
        guard !day.sessions.isEmpty else { return "\(name): rest" }
        let items = day.sessions.map { "\($0.title), \($0.status.rawValue)" }
        return "\(name): " + items.joined(separator: "; ")
    }
}

// MARK: - Goal progress

struct GoalProgressCard: View {
    let outline: PlanOutline
    let goal: TrainingGoal

    private var calendar: Calendar { .kinetix }
    private var currentIndex: Int? { outline.weekIndex(containing: .now, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    KXOverline(goal.displayName, color: KXColor.accent)
                    Text(headline).font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text(subline).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
                if let days = daysToEvent {
                    VStack(spacing: 0) {
                        Text("\(days)").font(KXFont.metricSmall).foregroundStyle(KXColor.ink)
                        Text(days == 1 ? "day to go" : "days to go").font(.caption2).foregroundStyle(KXColor.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // Phase bar: one segment per week, ordinal ramp by phase, current week outlined.
            HStack(spacing: 2) {
                ForEach(outline.weeks, id: \.index) { week in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(KXColor.phase(week.phase.index).opacity(isPast(week) || isCurrent(week) ? 1 : 0.45))
                        .frame(height: isCurrent(week) ? 16 : 10)
                        .overlay {
                            if isCurrent(week) {
                                RoundedRectangle(cornerRadius: 3).stroke(KXColor.ink, lineWidth: 1.5)
                            }
                        }
                }
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            HStack(spacing: KXSpacing.md) {
                ForEach(outline.blocks, id: \.firstWeek) { block in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(KXColor.phase(block.phase.index)).frame(width: 10, height: 10)
                        Text("\(block.phase.displayName) \(block.weekCount)w").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                }
            }
        }
        .kxCard()
        .accessibilityElement(children: .combine)
    }

    private func isCurrent(_ week: WeekTarget) -> Bool { week.index == currentIndex }
    private func isPast(_ week: WeekTarget) -> Bool { (currentIndex ?? -1) > week.index }

    private var headline: String {
        guard let index = currentIndex else { return "Your plan starts \(outline.startDate.formatted(.dateTime.weekday(.wide).day().month()))" }
        let week = outline.weeks[index]
        return "Week \(index + 1) of \(outline.weeks.count) · \(week.phase.displayName)"
    }

    private var subline: String {
        if let event = outline.eventDate { return "Event on \(event.formatted(.dateTime.day().month(.wide).year()))" }
        return "Rolling block: a new one is planned as this finishes"
    }

    private var daysToEvent: Int? {
        guard let event = outline.eventDate else { return nil }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: event)).day ?? 0)
    }
}

// MARK: - Recent PRs and race estimates

struct RecentRecordsCard: View {
    let records: [PersonalRecordModel]
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Label("Recent bests", systemImage: "trophy.fill")
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.ink)
            if records.isEmpty {
                Text("Your strength records appear here.").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 0) {
                    Text(PlanService.templates.exercise(id: record.recordKey)?.name ?? record.recordKey)
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
                    Text(DisplayFormat(units: units).weight(record.value) + " e1RM")
                        .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .kxCard()
    }
}

struct RaceEstimatesCard: View {
    let profile: AthleteProfile

    private struct Race { let meters: Double; let name: String }
    private static let races = [Race(meters: 5000, name: "5K"), Race(meters: 10000, name: "10K"),
                                Race(meters: 21097.5, name: "Half"), Race(meters: 42195, name: "Marathon")]

    private var zones: PaceZones { PaceZones(profile: profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Label("Race estimates", systemImage: "stopwatch")
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.ink)
            ForEach(Self.races, id: \.name) { race in
                HStack {
                    Text(race.name).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    Spacer()
                    Text(Units.formatMinutesSeconds(zones.predictedTime(distanceMeters: race.meters)))
                        .font(KXFont.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(KXColor.ink)
                }
                .accessibilityElement(children: .combine)
            }
            Text(profile.recentRace == nil ? "From your experience level" : "From your race time")
                .font(.caption2).foregroundStyle(KXColor.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .kxCard()
    }
}

// MARK: - Skip / swap

/// Lighter alternatives for a session, or skip it. Explains what changed.
struct SessionActionsSheet: View {
    let session: PlannedSessionModel
    let profile: AthleteProfile
    let onDone: ([String]) -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline("Session", color: KXColor.accent)
                    Text(session.title).font(KXFont.title).foregroundStyle(KXColor.ink)
                    Text("Not feeling it, or the day doesn't work? Swap for something lighter, move it, or skip. You can undo any change in \"What changed and why\".")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                KXOverline("Swap for")
                ForEach(BalanceService.swapOptions(for: session, profile: profile)) { option in
                    Button {
                        onDone(BalanceService.swap(session, to: option, profile: profile, in: context))
                    } label: {
                        HStack(spacing: KXSpacing.md) {
                            Image(systemName: option.systemImage)
                                .foregroundStyle(KXColor.accent)
                                .frame(width: 40, height: 40)
                                .background(KXColor.accentSoft, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                Text(option.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                Text(option.detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary)
                        }
                        .kxCard(padding: KXSpacing.md)
                    }
                    .buttonStyle(.plain)
                }
                let moves = BalanceService.moveOptions(for: session, profile: profile, in: context)
                if !moves.isEmpty {
                    KXOverline("Move to another day")
                    ForEach(moves) { option in
                        Button {
                            onDone(BalanceService.move(session, to: option.day, profile: profile, in: context))
                        } label: {
                            HStack(alignment: .top, spacing: KXSpacing.md) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(KXColor.accent)
                                    .frame(width: 40, height: 40)
                                    .background(KXColor.accentSoft, in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                    Text(Calendar.kinetix.isDateInToday(option.day) ? "Today"
                                         : option.day.formatted(.dateTime.weekday(.wide).day().month()))
                                        .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                    if let warning = option.warning {
                                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                            .symbolRenderingMode(.multicolor)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(KXColor.inkTertiary)
                            }
                            .kxCard(padding: KXSpacing.md)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("session.moveDay")
                    }
                }
                Button(role: .destructive) {
                    onDone(BalanceService.skip(session, profile: profile, in: context))
                } label: {
                    Label(session.movesWhenSkipped ? "Skip (we'll try to move it)" : "Skip this session", systemImage: "xmark.circle")
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
            }
            .padding(KXSpacing.xl)
        }
    }
}
