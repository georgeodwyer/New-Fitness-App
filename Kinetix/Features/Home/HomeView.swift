import SwiftUI
import SwiftData
import TrainingEngine

/// Dashboard: today's sessions, recovery check-in, body data from Apple Health, exertion (0–100)
/// against today's target with recovery and legs, daily strain, this week against plan, the week
/// at a glance, progress towards the goal, recent PRs and estimated race times. Cards can be
/// reordered and hidden (Edit dashboard); the layout syncs with the account.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query private var runs: [RunLogModel]
    @Query private var lifts: [StrengthLogModel]
    @Query(sort: \RecoveryCheckInModel.date, order: .reverse) private var checkIns: [RecoveryCheckInModel]
    @Query(sort: \PlanChangeModel.createdAt, order: .reverse) private var changes: [PlanChangeModel]
    @Query(filter: #Predicate<TrainingPlanModel> { $0.isActive }) private var plans: [TrainingPlanModel]
    @Query(sort: \PersonalRecordModel.achievedAt, order: .reverse) private var records: [PersonalRecordModel]
    @Query(filter: #Predicate<CoachingSettingsModel> { $0.deletedAt == nil }) private var settingsModels: [CoachingSettingsModel]
    @State private var showEditDashboard = false

    @State private var actionSession: PlannedSessionModel?
    @State private var detailSession: PlannedSessionModel?
    @State private var showCalendar = false
    @State private var openRun: RunLogModel?
    @State private var openLift: StrengthLogModel?
    /// Which of today's sessions the tile shows (nil: the first not yet done).
    @State private var tileIndex: Int?
    @State private var banner: String?
    @State private var showUpdates = false
    @State private var health = HealthService.shared
    @State private var integrations = IntegrationSettings.shared

    private var profile: AthleteProfile? { profiles.first?.profile }
    private var units: UnitSystem { profile?.units ?? UnitPreference.stored }

    /// Today's Health readings (none until last night's data is in).
    private var inputs: HealthInputs { HealthInputs.current }

    private var data: DashboardData {
        DashboardService.make(sessions: sessions, runs: runs, lifts: lifts, checkIns: checkIns, profile: profile,
                              external: integrations.loadWorkouts, health: inputs)
    }

    private var todaysSessions: [PlannedSessionModel] {
        let calendar = Calendar.kinetix
        return sessions
            .filter { !$0.isSoftDeleted && calendar.isDateInToday($0.date) && ($0.plan?.isActive ?? true) }
            .sorted { $0.slot == .morning && $1.slot == .evening }
    }

    /// Everything finished today, for the Done today card.
    private var doneToday: [DoneTodayCard.Item] {
        DoneTodayCard.items(runs: runs, lifts: lifts, external: integrations.loadWorkouts)
    }

    private var layout: DashboardLayout { settingsModels.first?.dashboardLayout ?? .default }

    var body: some View {
        let data = data
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Today", onNotifications: { showUpdates = true },
                                   onEditDashboard: { showEditDashboard = true })
                    greeting
                    if let banner { changeBanner(banner) }
                    if profile == nil { planPrompt }
                    ForEach(layout.visibleCards, id: \.self) { card in
                        dashboardCard(card, data: data)
                    }
                    // Once today's score is logged it moves out of the way, to the bottom.
                    if layout.visibleCards.contains(.checkIn), data.todaysCheckIn != nil {
                        checkInCard(data)
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .refreshable { await refreshEverything() }
            .background(KXColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailSession) { session in
                PlannedSessionDestination(session: session)
            }
            .navigationDestination(item: $openRun) { RunDetailView(log: $0, units: units) }
            .navigationDestination(item: $openLift) { StrengthSessionDetailView(log: $0, units: units) }
        }
        .sheet(isPresented: $showCalendar) { CalendarSheet() }
        .sheet(isPresented: $showEditDashboard) {
            EditDashboardView(layout: layout) { saveLayout($0) }
        }
        .sheet(item: $actionSession) { session in
            if let profile {
                SessionActionsSheet(session: session, profile: profile) { explanations in
                    actionSession = nil
                    banner = explanations.first
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showUpdates) {
            PlanUpdatesSheet(changes: Array(changes.filter { !$0.isSoftDeleted }.prefix(30)))
                .presentationDetents([.medium, .large])
        }
        .onAppear { putBackAutomaticChanges() }
    }

    /// The plan now changes on recovery only (when a session starts): once, put back any
    /// session the old load check eased.
    private func putBackAutomaticChanges() {
        let count = BalanceService.undoAutomaticChanges(in: context)
        if count > 0 {
            banner = "Put back \(count) session\(count == 1 ? "" : "s") eased for a spike in load. Your plan now adjusts on recovery only, when you start a session."
        }
    }

    /// Pull to refresh: re-reads Apple Health and syncs.
    private func refreshEverything() async {
        await health.refresh(force: true)
        await SyncService.shared.sync(context: context)
        WidgetSnapshotService.update(in: context)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            Text(greetingText)
                .font(KXFont.display)
                .foregroundStyle(KXColor.accent)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(KXFont.callout)
                .foregroundStyle(KXColor.inkSecondary)
        }
    }

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func changeBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(KXColor.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                KXOverline("Plan updated", color: KXColor.accent)
                Text(text).font(KXFont.callout).foregroundStyle(KXColor.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { banner = nil } label: { Image(systemName: "xmark").font(.caption) }
                .foregroundStyle(KXColor.inkSecondary)
                .accessibilityLabel("Dismiss")
        }
        .kxCard(.accent)
    }

    /// Shown until a plan exists: everything else on the dashboard works from recorded sessions.
    private var planPrompt: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Get a personalised plan", subtitle: "About two minutes")
            Text("Tell Kinetix your goal, week and equipment and it plans your runs and lifts so they work together. Or just record sessions from the Record tab.")
                .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: KXSpacing.sm) {
                Button("Build my plan") { router.selectedTab = .plan }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .accessibilityIdentifier("home.buildPlan")
                Button("Record") { router.selectedTab = .record }
                    .buttonStyle(.kx(.outlined, fullWidth: true))
            }
        }
        .kxCard(.accent)
    }

    /// Today's sessions stacked full width, then this week (when its card is on the dashboard),
    /// then the note about a lighter version when recovery is below par.
    private func todayTiles(data: DashboardData, showWeek: Bool) -> some View {
        let recovery = data.strain.recovery
        let start = plans.first?.startDate
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            TodaySessionCards(
                sessions: todaysSessions,
                planStart: start.flatMap { $0 > .now ? $0 : nil },
                format: DisplayFormat(units: units),
                onStart: { session in router.startPlanned(session, in: context) },
                onDetails: { detailSession = $0 },
                onActions: { actionSession = $0 }
            )
            if showWeek {
                ThisWeekTile(days: data.week) { showCalendar = true }
            }
            // On a below-par day, starting a session asks whether to reduce it (see AppRouter).
            if let recovery, let change = recovery.volumeChangeText, recovery.volumeMultiplier < 1 {
                Label("Recovery \(Int(recovery.score.rounded())): you'll be offered \(change) when you start today's session.",
                      systemImage: "arrow.down.right.circle")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
        }
    }

    /// The session the lighter-version offer is about: the one on the tile.
    private var offerSession: PlannedSessionModel? {
        let sessions = todaysSessions
        if let tileIndex, sessions.indices.contains(tileIndex) { return sessions[tileIndex] }
        return sessions.first { $0.status == .planned || $0.status == .swapped }
    }

    private func checkInCard(_ data: DashboardData) -> some View {
        CheckInCard(existing: data.todaysCheckIn, restingHeartRate: restingHeartRate, hrv: hrv,
                    sleepHours: inputs.sleepHours) { checkIn in
            saveCheckIn(checkIn)
        }
    }

    private var restingHeartRate: RestingHeartRateSignal? { inputs.restingHeartRate }

    private var hrv: HRVSignal? { inputs.hrv }

    @ViewBuilder
    private func dashboardCard(_ card: DashboardCard, data: DashboardData) -> some View {
        switch card {
        case .today:
            if profile != nil { todayTiles(data: data, showWeek: layout.visibleCards.contains(.weekStrip)) }
            if !doneToday.isEmpty {
                DoneTodayCard(items: doneToday, units: units, onOpenRun: { openRun = $0 }, onOpenLift: { openLift = $0 })
            }
        case .checkIn:
            // Before it's logged it sits where it's placed; afterwards it's at the bottom.
            if data.todaysCheckIn == nil { checkInCard(data) }
        case .body:
            BodyCard()
        case .load:
            StrainCard(report: data.strain, isWaitingForLastNight: inputs.isWaitingForLastNight)
        case .dailyLoad:
            DailyStrainChart(days: data.strain.days, target: data.strain.target)
        case .week:
            WeekProgressCard(data: data, units: units)
        case .weekStrip:
            // Shown under today's sessions; on its own only if Today is hidden.
            if profile == nil || !layout.visibleCards.contains(.today) { WeekStripCard(days: data.week) }
        case .goal:
            if let plan = plans.first, let outline = plan.outline {
                RaceCountdownCard(outline: outline, profile: profile)
            }
        case .records:
            RecentRecordsCard(records: Array(records.filter { $0.kindRaw == RecordKind.estimatedOneRepMax.rawValue }.prefix(3)), units: units)
            if let profile { RacePredictionsCard(profile: profile) }
        }
    }

    private func saveLayout(_ layout: DashboardLayout) {
        let settings: CoachingSettingsModel
        if let existing = settingsModels.first {
            settings = existing
        } else {
            settings = CoachingSettingsModel()
            context.insert(settings)
        }
        settings.dashboardLayout = layout
        settings.touch()
        try? context.save()
        SyncService.shared.requestSync()
    }

    private func saveCheckIn(_ answers: RecoveryCheckIn) {
        var checkIn = answers
        checkIn.restingHeartRateElevated = restingHeartRate?.isElevated ?? false
        checkIn.hrvSuppressed = hrv?.isSuppressed ?? false
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: .now)
        if let existing = checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            existing.sleep = checkIn.sleep
            existing.soreness = checkIn.soreness
            existing.legSoreness = checkIn.legSoreness
            existing.energy = checkIn.energy
            existing.touch()
        } else {
            context.insert(RecoveryCheckInModel(date: today, sleep: checkIn.sleep, soreness: checkIn.soreness, energy: checkIn.energy,
                                                legSoreness: checkIn.legSoreness))
        }
        try? context.save()
    }
}

extension RecoveryCheckInModel {
    var engineValue: RecoveryCheckIn { RecoveryCheckIn(sleep: sleep, soreness: soreness, energy: energy, legSoreness: legSoreness) }

    /// Includes this morning's resting heart rate and HRV from Apple Health, when known.
    func engineValue(restingHeartRate: RestingHeartRateSignal?, hrv: HRVSignal? = nil) -> RecoveryCheckIn {
        RecoveryCheckIn(sleep: sleep, soreness: soreness, energy: energy, legSoreness: legSoreness,
                        restingHeartRateElevated: restingHeartRate?.isElevated ?? false,
                        hrvSuppressed: hrv?.isSuppressed ?? false)
    }
}

#Preview {
    let container = try! Persistence.makeContainer(inMemory: true)
    SampleData.seed(into: container.mainContext)
    return HomeView()
        .environment(AppRouter())
        .modelContainer(container)
}

/// Recent automatic plan changes, each with what changed and why (opened from the bell).
struct PlanUpdatesSheet: View {
    let changes: [PlanChangeModel]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlanChangesView(changes: changes)
                .navigationTitle("What changed and why")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(KXColor.accent)
    }
}

/// On a fair recovery day: "Recovery 61 · Fair. Take the lighter version?" with one tap to switch.
struct LighterVersionOffer: View {
    let recovery: RecoveryScore
    let option: SwapOption
    let onTake: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.md) {
            Image(systemName: "battery.50percent")
                .foregroundStyle(KXColor.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery \(Int(recovery.score)) \u{00B7} \(recovery.band.title)")
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.ink)
                Text(option.detail)
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: KXSpacing.sm)
            Button("Go lighter", action: onTake)
                .buttonStyle(.kx(.secondary))
                .accessibilityIdentifier("today.goLighter")
        }
        .padding(KXSpacing.md)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swaps today's session for the lighter version")
    }
}
