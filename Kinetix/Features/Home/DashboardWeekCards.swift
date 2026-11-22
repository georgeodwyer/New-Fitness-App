import SwiftUI
import SwiftData
import TrainingEngine

// MARK: - This week vs plan

struct WeekProgressCard: View {
    let data: DashboardData
    let units: UnitSystem

    private var format: DisplayFormat { DisplayFormat(units: units) }

    /// How far through the week's plan you'd be by the end of today, if everything went to plan.
    private func expectedShare(_ discipline: Discipline, measure: (PlannedSessionModel) -> Double) -> Double {
        let sessions = data.week.flatMap(\.sessions).filter { $0.kind.discipline == discipline && $0.status != .skipped }
        let total = sessions.reduce(0) { $0 + measure($1) }
        guard total > 0 else { return 0 }
        let endOfToday = Calendar.kinetix.date(byAdding: .day, value: 1, to: Calendar.kinetix.startOfDay(for: .now)) ?? .now
        return sessions.filter { $0.date < endOfToday }.reduce(0) { $0 + measure($1) } / total
    }

    private var status: String {
        let a = data.adherence
        if a.total == 0 { return "Nothing planned" }
        if a.missed > 0 { return "\(a.missed) missed" }
        return "On track"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXOverline("This week vs plan · \(status)")
            bar("Run", value: data.actualRunMeters, planned: data.plannedRunMeters,
                expected: expectedShare(.run) { $0.estimatedDistanceMeters ?? 0 }, color: KXColor.run,
                text: "\(format.distance(data.actualRunMeters))/\(format.distance(data.plannedRunMeters, decimals: 0))")
            bar("Gym", value: data.actualLiftVolumeKg, planned: data.plannedLiftVolumeKg,
                expected: expectedShare(.strength) { _ in 1 }, color: KXColor.lift,
                text: "\(format.volume(data.actualLiftVolumeKg))/\(format.volume(data.plannedLiftVolumeKg))")
            Text("White tick: where the plan expects you to be by today")
                .font(KXFont.caption2)
                .foregroundStyle(KXColor.inkSecondary)
        }
        .kxCard()
        .accessibilityElement(children: .combine)
    }

    private func bar(_ label: String, value: Double, planned: Double, expected: Double, color: Color, text: String) -> some View {
        let share = planned > 0 ? min(value / planned, 1) : 0
        return HStack(spacing: KXSpacing.sm) {
            Text(label.uppercased())
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkSecondary)
                .frame(width: 36, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.surfaceTint)
                    Capsule().fill(color).frame(width: max(share > 0 ? 10 : 0, geo.size.width * share))
                    if planned > 0 {
                        Rectangle()
                            .fill(KXColor.ink)
                            .frame(width: 2, height: 18)
                            .offset(x: max(0, geo.size.width * expected - 1))
                    }
                }
                .frame(height: 10)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            Text(text)
                .font(KXFont.number(16, relativeTo: .callout))
                .foregroundStyle(KXColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 96, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(text)")
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
                        .font(KXFont.caption2)
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
                    Text("Not feeling it, or the day doesn't work? Swap for something lighter, move it to another day, trade days with another session, or skip. You can undo any change in \"What changed and why\".")
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
                            Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
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
                                Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                            }
                            .kxCard(padding: KXSpacing.md)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("session.moveDay")
                    }
                }
                let trades = BalanceService.daySwapOptions(for: session, profile: profile, in: context)
                if !trades.isEmpty {
                    KXOverline("Swap days with")
                    ForEach(trades) { option in
                        Button {
                            onDone(BalanceService.swapDays(session, with: option.other, profile: profile, in: context))
                        } label: {
                            HStack(alignment: .top, spacing: KXSpacing.md) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundStyle(option.other.kind.tint)
                                    .frame(width: 40, height: 40)
                                    .background(option.other.kind.tint.opacity(0.15), in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                    Text(option.other.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                    Text((Calendar.kinetix.isDateInToday(option.other.date) ? "Today"
                                          : option.other.date.formatted(.dateTime.weekday(.wide).day().month()))
                                         + " · they trade days")
                                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                    if let warning = option.warning {
                                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                            .symbolRenderingMode(.multicolor)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                            }
                            .kxCard(padding: KXSpacing.md)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("session.swapDays")
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

// MARK: - Latest best

/// Records on Today as one spotlight: the latest new best (with when), your race estimates in a
/// line underneath, and a link to all records in Activity.
struct LatestBestCard: View {
    let records: [PersonalRecordModel]
    let profile: AthleteProfile?
    let units: UnitSystem
    let onAll: () -> Void

    private var format: DisplayFormat { DisplayFormat(units: units) }

    private var latest: PersonalRecordModel? {
        records.filter { !$0.isSoftDeleted && $0.kindRaw == RecordKind.estimatedOneRepMax.rawValue }
            .max { $0.achievedAt < $1.achievedAt }
    }

    private func when(_ date: Date) -> String {
        let calendar = Calendar.kinetix
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        return days < 7 ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// "5K 23:41 · 10K 49:15 · Half 1:52:10".
    private var raceLine: String? {
        guard let profile else { return nil }
        let zones = PaceZones(vdot: FormService.predictionVDOT(for: profile))
        let races: [(String, Double)] = [("5K", 5000), ("10K", 10000), ("Half", 21097.5)]
        return races.map { "\($0.0) \(Units.formatMinutesSeconds(zones.predictedTime(distanceMeters: $0.1)))" }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .center, spacing: KXSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    if let record = latest {
                        KXOverline("New best · \(when(record.achievedAt))", color: KXColor.warning)
                        Text("\(PlanService.templates.exercise(id: record.recordKey)?.name ?? record.recordKey) \(format.weight(record.value))")
                            .font(KXFont.custom(.condensedBold, 24, relativeTo: .title3))
                            .textCase(.uppercase)
                            .foregroundStyle(KXColor.ink)
                            .lineLimit(2)
                        Text("Estimated 1-rep max").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    } else {
                        KXOverline("Race estimates", color: KXColor.run)
                        Text("From your current fitness").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    }
                }
                Spacer(minLength: KXSpacing.xs)
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(KXColor.warning)
                    .frame(width: 48, height: 48)
                    .background(KXColor.warning.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
            }
            if let raceLine {
                Text(raceLine)
                    .font(KXFont.callout.monospacedDigit())
                    .foregroundStyle(KXColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Divider().overlay(KXColor.border)
            HStack(spacing: KXSpacing.lg) {
                Button("All records", action: onAll)
                Spacer(minLength: 0)
            }
            .font(KXFont.callout)
            .foregroundStyle(KXColor.inkSecondary)
        }
        .padding(.vertical, KXSpacing.md)
        .padding(.leading, KXSpacing.lg)
        .padding(.trailing, KXSpacing.md)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.records")
    }
}
