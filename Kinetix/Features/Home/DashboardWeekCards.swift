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
            KXOverline("This week vs plan")
            HStack(alignment: .center, spacing: KXSpacing.lg) {
                adherenceRing
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    meters
                }
            }
            Divider().overlay(KXColor.border)
            adherence
        }
        .kxCard()
    }

    /// Plan adherence as a ring: the share of this week's sessions so far that were done.
    private var adherenceRing: some View {
        let percent = data.adherence.percent
        return ZStack {
            Circle().stroke(KXColor.surfaceTint, lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(percent ?? 0) / 100)
                .stroke(KXColor.success, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(percent.map { "\($0)%" } ?? "–")
                    .font(KXFont.number(26, relativeTo: .title2))
                    .foregroundStyle(KXColor.ink)
                Text("on plan").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan adherence \(percent.map { "\($0) percent" } ?? "not yet")")
    }

    @ViewBuilder private var meters: some View {
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
    }

    private func compactWeight(_ kg: Double) -> String { DisplayFormat(units: units).volume(kg) }

    private var adherence: some View {
        let a = data.adherence
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions so far").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                Spacer()
                Text("\(a.completed) of \(a.total)").font(KXFont.bodyEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
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
                .foregroundStyle(session.status == .skipped ? KXColor.inkTertiary : KXColor.onInverted)
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

// MARK: - Records

struct RecentRecordsCard: View {
    let records: [PersonalRecordModel]
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                KXOverline("Records")
                Spacer()
                Text("best estimated 1-rep max").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            if records.isEmpty {
                Text("Your strength records appear here after your first gym sessions.")
                    .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
            }
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if index > 0 { Divider().overlay(KXColor.border) }
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(KXColor.warning)
                        .frame(width: 34, height: 34)
                        .background(KXColor.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(PlanService.templates.exercise(id: record.recordKey)?.name ?? record.recordKey)
                            .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                        Text(record.achievedAt.formatted(.dateTime.day().month(.abbreviated)))
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer()
                    Text(DisplayFormat(units: units).weight(record.value))
                        .font(KXFont.number(22, relativeTo: .title3))
                        .foregroundStyle(KXColor.lift)
                }
                .accessibilityElement(children: .combine)
            }
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
