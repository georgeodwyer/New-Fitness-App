import SwiftUI
import SwiftData
import TrainingEngine

/// Dashboard: today's sessions, recovery check-in, body data from Apple Health, strain (0–21)
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

    private var layout: DashboardLayout { settingsModels.first?.dashboardLayout ?? .default }

    var body: some View {
        let data = data
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Dashboard", onNotifications: { showUpdates = true })
                    greeting
                    if let banner { changeBanner(banner) }
                    if profile == nil { planPrompt }
                    ForEach(layout.visibleCards, id: \.self) { card in
                        dashboardCard(card, data: data)
                    }
                    Button {
                        showEditDashboard = true
                    } label: {
                        Label("Edit dashboard", systemImage: "slider.horizontal.3")
                            .font(KXFont.captionEmphasis)
                    }
                    .foregroundStyle(KXColor.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("dashboard.edit")
                }
                .padding(KXSpacing.screenMargin)
            }
            .refreshable { await refreshEverything() }
            .background(KXColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
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
        .onAppear {
            // With Health connected, wait until it's been read today (the refresh below runs it).
            if !health.isConnected || health.isFreshToday { checkPlan() }
        }
        .onChange(of: health.lastRefresh) { checkPlan() }
    }

    /// Eases the coming days when load is high or your score is low. Runs once per day for
    /// each state of the Health data, so it looks again once last night's data arrives.
    private func checkPlan() {
        guard let profile else { return }
        let inputs = inputs
        let data = data
        let changed = BalanceService.autoAdjust(profile: profile, status: data.load.combined.status,
                                                checkIn: data.todaysCheckIn?.engineValue(restingHeartRate: inputs.restingHeartRate, hrv: inputs.hrv),
                                                in: context, ratio: data.load.combined.ratio,
                                                restingHeartRate: inputs.restingHeartRate, hrv: inputs.hrv,
                                                recovery: data.strain.recovery, dataKey: inputs.planCheckKey)
        if let first = changed.first { banner = first }
    }

    /// Pull to refresh: re-reads Apple Health and Strava, syncs, then checks the plan again.
    private func refreshEverything() async {
        await health.refresh(force: true)
        await StravaService.shared.importRecent(in: context, force: true)
        await SyncService.shared.sync(context: context)
        WidgetSnapshotService.update(in: context)
        checkPlan()
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            Text(greetingText)
                .font(KXFont.display)
                .foregroundStyle(KXColor.accent)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · here's your hybrid balance")
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

    private func todaySection(recovery: RecoveryScore?) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Today's sessions",
                            subtitle: todaysSessions.isEmpty ? nil : "\(todaysSessions.count) session\(todaysSessions.count == 1 ? "" : "s") planned")
            if todaysSessions.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    if let start = plans.first?.startDate, start > .now {
                        Label("Your plan starts \(start.formatted(.dateTime.weekday(.wide).day().month(.wide)))", systemImage: "calendar")
                            .font(KXFont.headline).foregroundStyle(KXColor.ink)
                        Text("Until then, an easy 20–30 minute run, a walk or rest is perfect. Fresh legs for day one.")
                            .font(KXFont.callout)
                            .foregroundStyle(KXColor.inkSecondary)
                    } else {
                        Label("Rest day", systemImage: "bed.double").font(KXFont.headline).foregroundStyle(KXColor.ink)
                        Text("Nothing scheduled today. Recovery is when the training sinks in.")
                            .font(KXFont.callout)
                            .foregroundStyle(KXColor.inkSecondary)
                    }
                }
                .kxCard(.tinted)
            } else {
                ForEach(Array(todaysSessions.enumerated()), id: \.element.id) { index, session in
                    VStack(spacing: 0) {
                        KXSessionCard(
                            overline: overline(for: session, index: index),
                            title: session.title,
                            detail: "\(session.summary) · \(Int(session.plannedDurationMinutes)) min",
                            kind: session.kind,
                            status: session.status,
                            onStart: session.kind.discipline == .crossTraining || session.kind.discipline == .mobility ? nil : {
                                router.start(ActiveSession(id: session.id, kind: session.kind, title: session.title))
                            }
                        )
                        if let profile, let recovery,
                           let lighter = BalanceService.lighterOption(for: session, profile: profile, recovery: recovery) {
                            LighterVersionOffer(recovery: recovery, option: lighter) {
                                let changed = BalanceService.takeLighter(session, option: lighter, recovery: recovery,
                                                                         profile: profile, in: context)
                                banner = changed.first
                            }
                            .padding(.top, KXSpacing.sm)
                        }
                        if session.status == .planned {
                            Button {
                                actionSession = session
                            } label: {
                                Label("Skip or swap", systemImage: "arrow.left.arrow.right")
                                    .font(KXFont.captionEmphasis)
                            }
                            .foregroundStyle(KXColor.inkSecondary)
                            .padding(.top, KXSpacing.xs)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func overline(for session: PlannedSessionModel, index: Int) -> String {
        let letters = ["A", "B", "C", "D"]
        var text = "Session \(letters[min(index, 3)]) · \(session.slot == .morning ? "Morning" : "Evening")"
        if session.status == .swapped { text += " · Swapped" }
        return text
    }

    private var restingHeartRate: RestingHeartRateSignal? { inputs.restingHeartRate }

    private var hrv: HRVSignal? { inputs.hrv }

    @ViewBuilder
    private func dashboardCard(_ card: DashboardCard, data: DashboardData) -> some View {
        switch card {
        case .today:
            if profile != nil { todaySection(recovery: data.strain.recovery) }
        case .checkIn:
            CheckInCard(existing: data.todaysCheckIn, restingHeartRate: restingHeartRate, hrv: hrv,
                        sleepHours: inputs.sleepHours) { checkIn in
                saveCheckIn(checkIn, status: data.load.combined.status, ratio: data.load.combined.ratio)
            }
        case .body:
            BodyCard()
        case .load:
            StrainCard(report: data.strain, isWaitingForLastNight: inputs.isWaitingForLastNight)
        case .dailyLoad:
            DailyStrainChart(days: data.strain.days, target: data.strain.target)
        case .week:
            WeekProgressCard(data: data, units: units)
        case .weekStrip:
            WeekStripCard(days: data.week)
        case .goal:
            if let plan = plans.first, let outline = plan.outline {
                GoalProgressCard(outline: outline, goal: profile?.goal ?? .balancedHybrid)
            }
        case .records:
            HStack(alignment: .top, spacing: KXSpacing.md) {
                RecentRecordsCard(records: Array(records.filter { $0.kindRaw == RecordKind.estimatedOneRepMax.rawValue }.prefix(3)), units: units)
                if let profile { RaceEstimatesCard(profile: profile) }
            }
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

    private func saveCheckIn(_ answers: RecoveryCheckIn, status: LoadStatus, ratio: Double?) {
        var checkIn = answers
        checkIn.restingHeartRateElevated = restingHeartRate?.isElevated ?? false
        checkIn.hrvSuppressed = hrv?.isSuppressed ?? false
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: .now)
        if let existing = checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            existing.sleep = checkIn.sleep
            existing.soreness = checkIn.soreness
            existing.energy = checkIn.energy
            existing.touch()
        } else {
            context.insert(RecoveryCheckInModel(date: today, sleep: checkIn.sleep, soreness: checkIn.soreness, energy: checkIn.energy))
        }
        try? context.save()
        if let profile {
            let changed = BalanceService.autoAdjust(profile: profile, status: status, checkIn: checkIn, in: context, force: true,
                                                    ratio: ratio, restingHeartRate: restingHeartRate, hrv: hrv,
                                                    recovery: StrainService.recovery(health: inputs, checkIn: checkIn),
                                                    dataKey: inputs.planCheckKey)
            if let first = changed.first { banner = first }
        }
    }
}

extension RecoveryCheckInModel {
    var engineValue: RecoveryCheckIn { RecoveryCheckIn(sleep: sleep, soreness: soreness, energy: energy) }

    /// Includes this morning's resting heart rate and HRV from Apple Health, when known.
    func engineValue(restingHeartRate: RestingHeartRateSignal?, hrv: HRVSignal? = nil) -> RecoveryCheckIn {
        RecoveryCheckIn(sleep: sleep, soreness: soreness, energy: energy, restingHeartRateElevated: restingHeartRate?.isElevated ?? false,
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
