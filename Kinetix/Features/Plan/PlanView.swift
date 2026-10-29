import SwiftUI
import SwiftData
import TrainingEngine

/// The upcoming plan, grouped by week with phase and running targets.
struct PlanView: View {
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<TrainingPlanModel> { $0.isActive }) private var plans: [TrainingPlanModel]
    @Query(sort: \PlanChangeModel.createdAt, order: .reverse) private var changes: [PlanChangeModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<RunLogModel> { $0.isFinished && $0.deletedAt == nil }) private var runs: [RunLogModel]
    @State private var showOnboarding = false
    @State private var showWalkthrough = false
    @State private var showCalendar = false
    @State private var showReview = false
    @State private var showBuilder = false
    @State private var showPause = false
    @Environment(AppRouter.self) private var router

    private var format: DisplayFormat { DisplayFormat(units: profiles.first?.units ?? UnitPreference.stored) }
    private var outline: PlanOutline? { plans.first?.outline }

    /// The calendar button, once there's a plan.
    private var calendarAction: (() -> Void)? {
        if profiles.isEmpty { return nil }
        return { showCalendar = true }
    }

    @Environment(\.modelContext) private var context
    /// Weeks not built yet, generated for display only.
    @State private var previews: [Int: GeneratedWeek] = [:]
    /// Weeks opened; the current week starts open.
    @State private var expanded: Set<Int> = []
    @State private var openedCurrentWeek = false
    /// Whether finished weeks of the programme are shown.
    @State private var showHistory = false

    private struct WeekGroup: Identifiable {
        let index: Int
        let target: WeekTarget?
        let days: [DayGroup]
        let isPreview: Bool
        var id: Int { index }

        var items: [Item] { days.flatMap(\.items) }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Item]
        var id: Date { day }
    }

    /// A built session (tap for detail) or a preview of one not built yet.
    private enum Item: Identifiable {
        case session(PlannedSessionModel)
        case preview(GeneratedSession)

        var id: String {
            switch self {
            case .session(let session): return session.id.uuidString
            case .preview(let session): return "\(session.date.timeIntervalSince1970)-\(session.slot.rawValue)-\(session.title)"
            }
        }
        var kind: SessionKind {
            switch self {
            case .session(let session): return session.kind
            case .preview(let session): return session.kind
            }
        }
        var meters: Double? {
            switch self {
            case .session(let session): return session.status == .skipped ? nil : session.estimatedDistanceMeters
            case .preview(let session): return session.estimatedDistanceMeters
            }
        }
    }

    /// The programme's weeks, past ones included (the current week shows its earlier days too).
    private var allWeeks: [WeekGroup] {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: .now)
        let activePlanID = plans.first?.id
        let planSessions = sessions.filter {
            !$0.isSoftDeleted && ($0.plan?.id == activePlanID || activePlanID == nil)
        }
        let byWeek = Dictionary(grouping: planSessions, by: \.weekIndex)
        let built = byWeek.keys.sorted().map { index in
            let byDay = Dictionary(grouping: byWeek[index] ?? []) { calendar.startOfDay(for: $0.date) }
            let days = byDay.keys.sorted().map { day in
                DayGroup(day: day, items: (byDay[day] ?? []).sorted { $0.slot == .morning && $1.slot == .evening }.map(Item.session))
            }
            return WeekGroup(index: index, target: target(index), days: days, isPreview: false)
        }
        let builtIndexes = Set(built.map(\.index))
        let later = previews.keys.sorted().filter { !builtIndexes.contains($0) }.compactMap { index -> WeekGroup? in
            guard let week = previews[index] else { return nil }
            let byDay = Dictionary(grouping: week.sessions.filter { $0.date >= today }) { calendar.startOfDay(for: $0.date) }
            let days = byDay.keys.sorted().map { day in
                DayGroup(day: day, items: (byDay[day] ?? []).sorted { $0.slot == .morning && $1.slot == .evening }.map(Item.preview))
            }
            return WeekGroup(index: index, target: week.target, days: days, isPreview: true)
        }
        return built + later
    }

    /// Finished weeks (before this one), oldest first.
    private func pastWeeks(_ all: [WeekGroup]) -> [WeekGroup] {
        let thisWeek = Calendar.kinetix.startOfISOWeek(for: .now)
        return all.filter { ($0.days.last?.day ?? .distantFuture) < thisWeek }
    }

    /// This week and the ones to come.
    private var weeks: [WeekGroup] {
        let all = allWeeks
        let past = Set(pastWeeks(all).map(\.index))
        return all.filter { !past.contains($0.index) }
    }

    private func target(_ index: Int) -> WeekTarget? {
        outline.flatMap { $0.weeks.indices.contains(index) ? $0.weeks[index] : nil }
    }

    /// Changes when the plan, its built weeks or the profile change (previews are rebuilt).
    private var previewKey: String {
        guard let plan = plans.first else { return "none" }
        return "\(plan.id)-\(plan.generatedWeekCount)-\(profiles.first?.updatedAt.timeIntervalSince1970 ?? 0)"
    }

    private func loadPreviews() async {
        guard let plan = plans.first, let profile = profiles.first?.profile else {
            previews = [:]
            return
        }
        previews = await PlanService.previewWeeksInBackground(for: plan, profile: profile, in: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXScreenHeader(title: "Training Plan", onCalendar: calendarAction)
                    if let plan = plans.first, plan.isPaused { PausedPlanCard(plan: plan) }
                    if profiles.isEmpty {
                        PlanIntroCard { showOnboarding = true }
                    }
                    if let outline {
                        RaceCountdownCard(outline: outline, profile: profiles.first?.profile)
                        WeeklyDistanceCard(outline: outline, runs: runs, format: format, sessions: plans.first?.sessions ?? [])
                        Button {
                            showReview = true
                        } label: {
                            Label("Week review & next week", systemImage: "calendar.badge.checkmark")
                        }
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                        .accessibilityIdentifier("plan.weekReview")
                        Button {
                            showBuilder = true
                        } label: {
                            Label(outline.customPlan == nil ? "Build my own plan" : "Edit my plan", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.kx(.outlined, fullWidth: true))
                        .accessibilityIdentifier("plan.builder")
                        if let plan = plans.first, !plan.isPaused {
                            Button {
                                showPause = true
                            } label: {
                                Label("Pause plan (ill, injured or away)", systemImage: "pause.circle")
                            }
                            .buttonStyle(.kx(.outlined, fullWidth: true))
                            .accessibilityIdentifier("plan.pause")
                        }
                    }
                    if weeks.isEmpty && !profiles.isEmpty {
                        Text("No sessions planned yet.")
                            .font(KXFont.callout)
                            .foregroundStyle(KXColor.inkSecondary)
                            .kxCard(.tinted)
                    }
                    let all = allWeeks
                    let past = pastWeeks(all)
                    if !past.isEmpty { historySection(past) }
                    ForEach(all.filter { week in !past.contains { $0.index == week.index } }) { week in weekSection(week) }
                    if !changes.isEmpty { changesLink }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .task(id: previewKey) { await loadPreviews() }
            .onChange(of: weeks.first?.index, initial: true) { _, first in
                // Open the current week once; after that, what's open is up to the runner.
                guard !openedCurrentWeek, let first else { return }
                expanded.insert(first)
                openedCurrentWeek = true
            }
            .sheet(isPresented: $showCalendar) { CalendarSheet() }
            .sheet(isPresented: $showPause) { PausePlanSheet().presentationDetents([.large]) }
            .fullScreenCover(isPresented: $showBuilder) {
                PlanBuilderView(existing: outline?.customPlan)
            }
            .sheet(isPresented: $showReview) {
                WeeklyReviewSheet(units: profiles.first?.units ?? UnitPreference.stored)
            }
            .navigationDestination(for: PlannedSessionModel.self) { session in
                PlannedSessionDestination(session: session)
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

    /// "Earlier weeks": the programme so far, folded away until opened.
    @ViewBuilder
    private func historySection(_ past: [WeekGroup]) -> some View {
        let sessions = past.flatMap(\.items).compactMap { item -> PlannedSessionModel? in
            if case .session(let session) = item { return session }
            return nil
        }
        let done = sessions.filter { $0.status == .completed }.count
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showHistory.toggle() }
        } label: {
            HStack(spacing: KXSpacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(KXColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text("Earlier weeks").font(KXFont.headline).foregroundStyle(KXColor.ink)
                    Text("\(past.count) week\(past.count == 1 ? "" : "s") · \(done) of \(sessions.count) sessions done")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(KXColor.inkTertiary)
                    .rotationEffect(.degrees(showHistory ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, KXSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(showHistory ? "Hides the weeks you've finished" : "Shows the weeks you've finished")
        .accessibilityIdentifier("plan.history")
        if showHistory {
            ForEach(past) { week in weekSection(week) }
        }
    }

    private func weekSection(_ week: WeekGroup) -> some View {
        let isOpen = expanded.contains(week.index)
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(week.index) } else { expanded.insert(week.index) }
                }
            } label: {
                weekHeader(week, isOpen: isOpen)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides this week's sessions" : "Shows this week's sessions")
            if isOpen {
                // The coach's note for the week.
                let notes = week.isPreview ? (previews[week.index]?.notes ?? []) : (plans.first?.notes(forWeek: week.index) ?? [])
                if !notes.isEmpty {
                    HStack(alignment: .top, spacing: KXSpacing.sm) {
                        Image(systemName: "quote.opening")
                            .font(KXFont.caption)
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
                if week.isPreview {
                    Label("Preview: these sessions are set about two weeks ahead and may adjust as you train.",
                          systemImage: "eye")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(week.days) { day in
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        KXOverline(day.day.formatted(.dateTime.weekday(.wide).day().month()))
                        ForEach(day.items) { item in
                            switch item {
                            case .session(let session):
                                NavigationLink(value: session) { sessionRow(session) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("plan.session")
                            case .preview(let session):
                                previewRow(session)
                            }
                        }
                    }
                }
            }
        }
    }

    /// "Week 3 · Build" with the week's dates and "3 runs · 2 lifts · 28 km".
    private func weekHeader(_ week: WeekGroup, isOpen: Bool) -> some View {
        HStack(alignment: .center, spacing: KXSpacing.sm) {
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                HStack(spacing: KXSpacing.sm) {
                    Text("Week \(week.index + 1)").font(KXFont.headline).foregroundStyle(KXColor.ink)
                    if let target = week.target {
                        KXChip(text: target.phase.displayName, variant: .secondary)
                        if target.isRecoveryWeek { KXChip(text: "Recovery", variant: .outlined) }
                    }
                    if week.isPreview { KXChip(text: "Preview", variant: .outlined) }
                }
                Text(summary(week))
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.down")
                .font(KXFont.captionEmphasis)
                .foregroundStyle(KXColor.inkTertiary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .accessibilityHidden(true)
        }
        .padding(.vertical, KXSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func summary(_ week: WeekGroup) -> String {
        let items = week.items
        let runs = items.filter { $0.kind.discipline == .run }.count
        let lifts = items.filter { $0.kind.discipline == .strength }.count
        let other = items.count - runs - lifts
        var parts: [String] = []
        if let first = week.days.first?.day, let last = week.days.last?.day {
            parts.append(first == last ? first.formatted(.dateTime.day().month(.abbreviated))
                         : "\(first.formatted(.dateTime.day().month(.abbreviated)))–\(last.formatted(.dateTime.day().month(.abbreviated)))")
        }
        if runs > 0 { parts.append("\(runs) run\(runs == 1 ? "" : "s")") }
        if lifts > 0 { parts.append("\(lifts) lift\(lifts == 1 ? "" : "s")") }
        if other > 0 { parts.append("\(other) other") }
        let meters = items.compactMap(\.meters).reduce(0, +)
        let distance = meters > 0 ? meters : (week.target?.runVolumeMeters ?? 0)
        if distance > 0 { parts.append(format.distance(distance, decimals: 0)) }
        return parts.joined(separator: " · ")
    }

    private func sessionRow(_ session: PlannedSessionModel) -> some View {
        let done = session.status == .completed
        let skipped = session.status == .skipped
        return HStack(spacing: KXSpacing.md) {
            RoundedRectangle(cornerRadius: 2)
                .fill(session.kind.tint.opacity(done || skipped ? 0.45 : 1))
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)
            Image(systemName: done ? "checkmark.circle.fill" : session.kind.symbolName)
                .foregroundStyle(done ? KXColor.success : session.kind.tint)
                .frame(width: 34, height: 34)
                .background((done ? KXColor.success : session.kind.tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(session.title).font(KXFont.bodyEmphasis).foregroundStyle(skipped ? KXColor.inkTertiary : KXColor.ink)
                    .strikethrough(skipped)
                Text("\(session.summary) · \(Int(session.plannedDurationMinutes)) min")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            if done {
                KXChip(text: "Done", systemImage: "checkmark", variant: .success)
            } else if skipped {
                KXChip(text: "Skipped", variant: .outlined)
            }
            Image(systemName: "chevron.right")
                .font(KXFont.caption)
                .foregroundStyle(KXColor.inkTertiary)
                .accessibilityHidden(true)
        }
        .kxCard(padding: KXSpacing.md)
        .accessibilityElement(children: .combine)
    }

    /// A session not built yet: shown, but not opened or changed until it's built.
    private func previewRow(_ session: GeneratedSession) -> some View {
        HStack(spacing: KXSpacing.md) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(session.kind.tint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 4, height: 36)
                .accessibilityHidden(true)
            Image(systemName: session.kind.symbolName)
                .foregroundStyle(session.kind.tint.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(session.kind.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(session.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text("\(session.summary) · \(Int(session.plannedDurationMinutes)) min")
                    .font(KXFont.caption)
                    .foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
        }
        .kxCard(.tinted, padding: KXSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), preview")
    }

    /// One line to the full history of changes (the explanations live there).
    private var changesLink: some View {
        NavigationLink {
            PlanChangesView(changes: Array(changes))
                .navigationTitle("What changed and why")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack {
                Label("Why your plan looks like this", systemImage: "questionmark.circle")
                    .font(KXFont.bodyEmphasis)
                    .foregroundStyle(KXColor.ink)
                Spacer()
                Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
            .kxCard(.tinted, padding: KXSpacing.md)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.allChanges")
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
            Text("Answer a few questions (two minutes) for a running and lifting plan built around your week.")
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
            Text("Or just record sessions from the Record tab.")
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
