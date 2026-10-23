import SwiftUI
import SwiftData
import TrainingEngine

/// The upcoming plan, grouped by week with phase and running targets.
struct PlanView: View {
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<TrainingPlanModel> { $0.isActive }) private var plans: [TrainingPlanModel]
    @Query(sort: \PlanChangeModel.createdAt, order: .reverse) private var changes: [PlanChangeModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @State private var showOnboarding = false
    @State private var showWalkthrough = false
    @Environment(AppRouter.self) private var router

    private var format: DisplayFormat { DisplayFormat(units: profiles.first?.units ?? UnitPreference.stored) }
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
                    if profiles.isEmpty {
                        PlanIntroCard { showOnboarding = true }
                    }
                    if let outline { overview(outline) }
                    if weeks.isEmpty && !profiles.isEmpty {
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
            .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
                // Just built a plan: show the app tour once.
                if Walkthrough.isPending && !profiles.isEmpty { showWalkthrough = true }
            }) {
                OnboardingFlowView(onClose: { showOnboarding = false })
            }
            .fullScreenCover(isPresented: $showWalkthrough) {
                WalkthroughView { openToday in
                    showWalkthrough = false
                    if openToday { router.selectedTab = .today }
                }
            }
            // Building the plan saves a profile: close the set-up and show the new plan.
            .onChange(of: profiles.count) { _, count in
                if count > 0 { showOnboarding = false }
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
            // The coach's note for the week.
            let notes = plans.first?.notes(forWeek: week.index) ?? []
            if !notes.isEmpty {
                HStack(alignment: .top, spacing: KXSpacing.sm) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(KXColor.accent)
                        .accessibilityHidden(true)
                    Text(notes.joined(separator: " "))
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Coach's note: \(notes.joined(separator: " "))")
            }
            ForEach(week.days) { day in
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline(day.day.formatted(.dateTime.weekday(.wide).day().month()))
                    ForEach(day.sessions) { session in
                        NavigationLink(value: session) { sessionRow(session) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("plan.session")
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: PlannedSessionModel) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: session.kind.symbolName)
                .foregroundStyle(session.kind.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(session.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text("\(session.summary) · \(Int(session.plannedDurationMinutes)) min")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
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
            ForEach(changes.prefix(4)) { change in
                Label(change.summary, systemImage: change.cause.symbol)
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            NavigationLink {
                PlanChangesView(changes: Array(changes))
                    .navigationTitle("What changed and why")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("See every change, before and after", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.accent)
            }
            .accessibilityIdentifier("plan.allChanges")
        }
        .kxCard(.tinted)
    }

    /// Phases are a sequence, so they use one hue from light (base) to dark (taper).
    private func color(for phase: TrainingPhase) -> Color {
        KXColor.phase(TrainingPhase.allCases.firstIndex(of: phase) ?? 0)
    }
}

/// Shown on the Plan tab until a plan exists: what a plan does and a button to build one.
struct PlanIntroCard: View {
    let onBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            KXAccentHeadline(plain: "Your training,", accented: "planned")
            Text("Answer a few questions (about two minutes) and Kinetix builds a running and lifting plan around your goal, your week and your equipment, then keeps it balanced as you train.")
                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                point("calendar", "Sessions placed so running and lifting don't undermine each other")
                point("speedometer", "Pace targets and audio coaching for every run")
                point("chart.line.uptrend.xyaxis", "Weights that progress as you get stronger")
                point("arrow.triangle.2.circlepath", "Eases off automatically when load or recovery says so")
            }
            Button("Build my plan", action: onBuild)
                .buttonStyle(.kx(.primary, fullWidth: true))
                .accessibilityIdentifier("plan.build")
            Text("Don't want a plan? You can still record runs and workouts from the Record tab.")
                .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
        }
        .kxCard()
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(KXFont.callout).foregroundStyle(KXColor.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(KXColor.accent)
        }
    }
}
