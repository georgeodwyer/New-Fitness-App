import SwiftUI
import SwiftData
import TrainingEngine

/// Dashboard: today's sessions, recovery check-in, training load (running, lifting,
/// combined; acute:chronic ratio), this week against plan, the week at a glance,
/// progress towards the goal, recent PRs and estimated race times.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query private var profiles: [UserProfileModel]
    @Query private var runs: [RunLogModel]
    @Query private var lifts: [StrengthLogModel]
    @Query(sort: \RecoveryCheckInModel.date, order: .reverse) private var checkIns: [RecoveryCheckInModel]
    @Query(sort: \PlanChangeModel.createdAt, order: .reverse) private var changes: [PlanChangeModel]
    @Query(filter: #Predicate<TrainingPlanModel> { $0.isActive }) private var plans: [TrainingPlanModel]
    @Query(sort: \PersonalRecordModel.achievedAt, order: .reverse) private var records: [PersonalRecordModel]

    @State private var actionSession: PlannedSessionModel?
    @State private var banner: String?

    private var profile: AthleteProfile? { profiles.first?.profile }
    private var units: UnitSystem { profile?.units ?? .metric }

    private var data: DashboardData {
        DashboardService.make(sessions: sessions, runs: runs, lifts: lifts, checkIns: checkIns, profile: profile)
    }

    private var todaysSessions: [PlannedSessionModel] {
        let calendar = Calendar.kinetix
        return sessions
            .filter { !$0.isSoftDeleted && calendar.isDateInToday($0.date) && ($0.plan?.isActive ?? true) }
            .sorted { $0.slot == .morning && $1.slot == .evening }
    }

    var body: some View {
        let data = data
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXScreenHeader(title: "Dashboard", onNotifications: {})
                greeting
                if let banner { changeBanner(banner) }
                todaySection
                CheckInCard(existing: data.todaysCheckIn) { checkIn in saveCheckIn(checkIn, status: data.load.combined.status) }
                LoadHeroCard(report: data.load)
                DailyLoadChart(daily: data.load.daily)
                WeekProgressCard(data: data, units: units)
                WeekStripCard(days: data.week)
                if let plan = plans.first, let outline = plan.outline {
                    GoalProgressCard(outline: outline, goal: profile?.goal ?? .balancedHybrid)
                }
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    RecentRecordsCard(records: Array(records.filter { $0.kindRaw == RecordKind.estimatedOneRepMax.rawValue }.prefix(3)), units: units)
                    if let profile { RaceEstimatesCard(profile: profile) }
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .sheet(item: $actionSession) { session in
            if let profile {
                SessionActionsSheet(session: session, profile: profile) { explanations in
                    actionSession = nil
                    banner = explanations.first
                }
                .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            guard let profile else { return }
            let changed = BalanceService.autoAdjust(profile: profile, status: data.load.combined.status,
                                                    checkIn: data.todaysCheckIn?.engineValue, in: context)
            if let first = changed.first { banner = first }
        }
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

    private var todaySection: some View {
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
                                router.activeSession = ActiveSession(id: session.id, kind: session.kind, title: session.title)
                            }
                        )
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
        if session.isKey { text += " · Key" }
        if session.status == .swapped { text += " · Swapped" }
        return text
    }

    private func saveCheckIn(_ checkIn: RecoveryCheckIn, status: LoadStatus) {
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
            let changed = BalanceService.autoAdjust(profile: profile, status: status, checkIn: checkIn, in: context, force: true)
            if let first = changed.first { banner = first }
        }
    }
}

extension RecoveryCheckInModel {
    var engineValue: RecoveryCheckIn { RecoveryCheckIn(sleep: sleep, soreness: soreness, energy: energy) }
}

#Preview {
    let container = try! Persistence.makeContainer(inMemory: true)
    SampleData.seed(into: container.mainContext)
    return HomeView()
        .environment(AppRouter())
        .modelContainer(container)
}
