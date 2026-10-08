import SwiftUI
import SwiftData
import TrainingEngine

/// The upcoming plan, grouped by week with phase and running targets.
struct PlanView: View {
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<TrainingPlanModel> { $0.isActive }) private var plans: [TrainingPlanModel]
    @Query(sort: \PlanChangeModel.createdAt, order: .reverse) private var changes: [PlanChangeModel]
    @Query private var profiles: [UserProfileModel]

    private var format: DisplayFormat { DisplayFormat(units: profiles.first?.units ?? .metric) }
    private var outline: PlanOutline? { plans.first?.outline }

    private struct WeekGroup: Identifiable {
        let index: Int
        let target: WeekTarget?
        let days: [DayGroup]
        var id: Int { index }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let sessions: [PlannedSessionModel]
        var id: Date { day }
    }

    private var weeks: [WeekGroup] {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: .now)
        let activePlanID = plans.first?.id
        let upcoming = sessions.filter {
            !$0.isSoftDeleted && $0.date >= today && ($0.plan?.id == activePlanID || activePlanID == nil)
        }
        let byWeek = Dictionary(grouping: upcoming, by: \.weekIndex)
        return byWeek.keys.sorted().map { index in
            let byDay = Dictionary(grouping: byWeek[index] ?? []) { calendar.startOfDay(for: $0.date) }
            let days = byDay.keys.sorted().map { day in
                DayGroup(day: day, sessions: (byDay[day] ?? []).sorted { $0.slot == .morning && $1.slot == .evening })
            }
            let target = outline.flatMap { $0.weeks.indices.contains(index) ? $0.weeks[index] : nil }
            return WeekGroup(index: index, target: target, days: days)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Training Plan")
                    if let outline { overview(outline) }
                    if weeks.isEmpty {
                        Text("No sessions planned yet.")
                            .font(KXFont.callout)
                            .foregroundStyle(KXColor.inkSecondary)
                            .kxCard(.tinted)
                    }
                    ForEach(weeks) { week in weekSection(week) }
                    if !changes.isEmpty { changesSection }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationDestination(for: PlannedSessionModel.self) { session in
                SessionDetailView(session: session)
            }
        }
    }

    private func overview(_ outline: PlanOutline) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader(outline.eventDate == nil ? "Rolling block" : "Road to your event",
                            subtitle: outline.eventDate.map { "Event: \($0.formatted(.dateTime.day().month(.wide).year()))" })
            HStack(spacing: KXSpacing.xxs) {
                ForEach(outline.blocks, id: \.firstWeek) { block in
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        Capsule()
                            .fill(color(for: block.phase))
                            .frame(height: 8)
                        Text(block.phase.displayName).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(Double(block.weekCount))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(block.phase.displayName), \(block.weekCount) weeks")
                }
            }
        }
        .kxCard()
    }

    private func weekSection(_ week: WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Text("Week \(week.index + 1)").font(KXFont.headline).foregroundStyle(KXColor.ink)
                if let target = week.target {
                    KXChip(text: target.phase.displayName, variant: .secondary)
                    if target.isRecoveryWeek { KXChip(text: "Recovery", variant: .outlined) }
                }
                Spacer()
                if let target = week.target {
                    Text("\(format.distance(target.runVolumeMeters, decimals: 0)) running")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
            }
            ForEach(week.days) { day in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(day.day.formatted(.dateTime.weekday(.wide).day().month()))
                    ForEach(day.sessions) { session in
                        NavigationLink(value: session) { sessionRow(session) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: PlannedSessionModel) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: session.kind.symbolName)
                .foregroundStyle(session.kind.discipline == .run ? KXColor.accent : KXColor.slate)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(session.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text("\(session.summary) · \(Int(session.plannedDurationMinutes)) min")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            if session.isKey {
                KXChip(text: "Key", systemImage: "star.fill", variant: .secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(KXColor.inkTertiary)
                .accessibilityHidden(true)
        }
        .kxCard(padding: KXSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader("Why your plan looks like this")
            ForEach(changes.prefix(6)) { change in
                Label(change.summary, systemImage: "info.circle")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
        }
        .kxCard(.tinted)
    }

    private func color(for phase: TrainingPhase) -> Color {
        switch phase {
        case .base: return KXColor.teal
        case .build: return KXColor.accent
        case .peak: return KXColor.danger
        case .taper: return KXColor.slate
        }
    }
}
