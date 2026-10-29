import SwiftUI
import SwiftData
import TrainingEngine

/// A month calendar of the plan and what you've done: dots for each session, the race day
/// flagged, and the chosen day's sessions underneath (tap to open, ••• to move, swap or
/// skip). Goes back two years and forward three. Shown as a sheet with its own navigation
/// (`CalendarSheet`): pushed onto Today's or the Plan tab's stack it looped forever.
struct TrainingCalendarView: View {
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<TrainingPlanModel> { $0.isActive }) private var plans: [TrainingPlanModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Query(filter: #Predicate<RunLogModel> { $0.isFinished && $0.deletedAt == nil }) private var runs: [RunLogModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished && $0.deletedAt == nil }) private var lifts: [StrengthLogModel]
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var month = Calendar.kinetix.startOfMonth(for: .now)
    @State private var selected = Calendar.kinetix.startOfDay(for: .now)
    @State private var previews: [Int: GeneratedWeek] = [:]
    @State private var openSession: PlannedSessionModel?
    @State private var openRun: RunLogModel?
    @State private var openLift: StrengthLogModel?
    @State private var actionSession: PlannedSessionModel?
    @State private var banner: String?
    @State private var showRearrange = false

    private let calendar = Calendar.kinetix
    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }
    private var format: DisplayFormat { DisplayFormat(units: units) }
    private var outline: PlanOutline? { plans.first?.outline }

    private var firstMonth: Date { calendar.date(byAdding: .month, value: -24, to: calendar.startOfMonth(for: .now)) ?? month }
    private var lastMonth: Date { calendar.date(byAdding: .month, value: 36, to: calendar.startOfMonth(for: .now)) ?? month }

    // MARK: Entries

    /// Something on a day: a planned session, a preview of one not built yet, or a workout
    /// done outside the plan.
    enum Entry: Identifiable {
        case planned(PlannedSessionModel)
        case preview(GeneratedSession)
        case run(RunLogModel)
        case lift(StrengthLogModel)

        var id: String {
            switch self {
            case .planned(let s): return s.id.uuidString
            case .preview(let s): return "p-\(s.date.timeIntervalSince1970)-\(s.slot.rawValue)-\(s.title)"
            case .run(let r): return r.id.uuidString
            case .lift(let l): return l.id.uuidString
            }
        }
    }

    /// Everything by day.
    private var byDay: [Date: [Entry]] {
        var result: [Date: [Entry]] = [:]
        let activeID = plans.first?.id
        let live = sessions.filter { !$0.isSoftDeleted && ($0.plan == nil || $0.plan?.id == activeID || $0.status == .completed) }
        for session in live { result[calendar.startOfDay(for: session.date), default: []].append(.planned(session)) }
        let builtWeeks = Set(live.map(\.weekIndex))
        for (index, week) in previews where !builtWeeks.contains(index) {
            for session in week.sessions { result[calendar.startOfDay(for: session.date), default: []].append(.preview(session)) }
        }
        // Workouts not linked to a planned session.
        let plannedIDs = Set(sessions.map(\.id))
        for run in runs where run.plannedSessionId.map({ !plannedIDs.contains($0) }) ?? true {
            result[calendar.startOfDay(for: run.startedAt), default: []].append(.run(run))
        }
        for lift in lifts where lift.plannedSessionId.map({ !plannedIDs.contains($0) }) ?? true {
            result[calendar.startOfDay(for: lift.startedAt), default: []].append(.lift(lift))
        }
        return result
    }

    var body: some View {
        let days = byDay
        let outline = outline
        let eventDay = outline?.eventDate.map { calendar.startOfDay(for: $0) }
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                monthHeader(eventDay: eventDay)
                monthGrid(days, outline: outline, eventDay: eventDay)
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width < -50 { step(1) } else if value.translation.width > 50 { step(-1) }
                    })
                legend
                Button {
                    showRearrange = true
                } label: {
                    Label("Rearrange this week or next", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.kx(.outlined, fullWidth: true))
                .accessibilityIdentifier("calendar.rearrange")
                if let banner {
                    Label(banner, systemImage: "info.circle")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .kxCard(.tinted)
                }
                dayList(days[selected] ?? [], outline: outline, eventDay: eventDay)
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") {
                    month = calendar.startOfMonth(for: .now)
                    selected = calendar.startOfDay(for: .now)
                }
            }
        }
        .tint(KXColor.accent)
        .task(id: plans.first.map { "\($0.id)-\($0.generatedWeekCount)" } ?? "none") { await loadPreviews() }
        .navigationDestination(item: $openSession) { SessionDetailView(session: $0) }
        .navigationDestination(item: $openRun) { RunDetailView(log: $0, units: units) }
        .navigationDestination(item: $openLift) { StrengthSessionDetailView(log: $0, units: units) }
        .sheet(isPresented: $showRearrange) { WeekRearrangeView() }
        .sheet(item: $actionSession) { session in
            if let profile = profiles.first?.profile {
                SessionActionsSheet(session: session, profile: profile) { explanations in
                    actionSession = nil
                    banner = explanations.first
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func loadPreviews() async {
        guard let plan = plans.first, let profile = profiles.first?.profile else { previews = [:]; return }
        previews = await PlanService.previewWeeksInBackground(for: plan, profile: profile, in: context)
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month), next >= firstMonth, next <= lastMonth else { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = next }
    }

    // MARK: Month

    private func monthHeader(eventDay: Date?) -> some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(month <= firstMonth)
                .accessibilityLabel("Previous month")
            Spacer()
            VStack(spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(KXFont.custom(.condensedBold, 24, relativeTo: .title2))
                    .textCase(.uppercase)
                    .foregroundStyle(KXColor.ink)
                if let event = eventDay {
                    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: event).day ?? 0
                    Button {
                        month = calendar.startOfMonth(for: event)
                        selected = event
                    } label: {
                        Label(days > 0 ? "Race in \(days) days" : (days == 0 ? "Race day today" : "Race day"), systemImage: "flag.checkered")
                            .font(KXFont.captionEmphasis)
                            .foregroundStyle(KXColor.ink)
                            .padding(.horizontal, KXSpacing.md)
                            .padding(.vertical, KXSpacing.xs)
                            .background(KXColor.surfaceTint, in: Capsule())
                    }
                    .accessibilityHint("Shows race day")
                }
            }
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(month >= lastMonth)
                .accessibilityLabel("Next month")
        }
    }

    private func monthGrid(_ days: [Date: [Entry]], outline: PlanOutline?, eventDay: Date?) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let cells = monthCells
        return VStack(spacing: KXSpacing.xs) {
            // Weekday letters in their own row: sharing the grid with the days gave two
            // items the same id, which crashes a lazy grid.
            HStack(spacing: 2) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        dayCell(day, entries: days[day] ?? [], outline: outline, eventDay: eventDay)
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
        .kxCard(padding: KXSpacing.sm)
    }

    /// The month's days with blanks before the 1st so Monday is first.
    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month) // 1 = Sunday
        let leading = (firstWeekday + 5) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days.map(Optional.some)
    }

    private func dayCell(_ day: Date, entries: [Entry], outline: PlanOutline?, eventDay: Date?) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isRace = eventDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let phase = phaseColor(for: day, outline: outline)
        return Button { selected = day } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle().fill(KXColor.accent)
                    } else if isToday {
                        Circle().stroke(KXColor.accent, lineWidth: 1.5)
                    }
                    Text("\(calendar.component(.day, from: day))")
                        .font(KXFont.callout.weight(isToday || isSelected ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(isSelected ? KXColor.onAccent : KXColor.ink)
                }
                .frame(width: 30, height: 30)
                HStack(spacing: 2) {
                    if isRace {
                        Image(systemName: "flag.checkered").font(.system(size: 9, weight: .bold)).foregroundStyle(KXColor.ink)
                    }
                    ForEach(Array(entries.prefix(isRace ? 2 : 3).enumerated()), id: \.offset) { _, entry in
                        dot(entry)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(alignment: .bottom) {
                // A thin line in the phase colour under days inside the plan.
                if let phase { Capsule().fill(phase.opacity(0.35)).frame(height: 2).padding(.horizontal, 6) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayLabel(day, entries: entries, isRace: isRace))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func phaseColor(for day: Date, outline: PlanOutline?) -> Color? {
        guard let outline, let index = outline.weekIndex(containing: day, calendar: calendar) else { return nil }
        return KXColor.phase(TrainingPhase.allCases.firstIndex(of: outline.weeks[index].phase) ?? 0)
    }

    /// Filled when done, a ring when still to do, faint when skipped or a preview.
    @ViewBuilder private func dot(_ entry: Entry) -> some View {
        switch entry {
        case .planned(let session):
            switch session.status {
            case .completed: Circle().fill(session.kind.tint).frame(width: 6, height: 6)
            case .skipped: Circle().fill(KXColor.border).frame(width: 6, height: 6)
            default: Circle().stroke(session.kind.tint, lineWidth: 1.5).frame(width: 6, height: 6)
            }
        case .preview(let session):
            Circle().stroke(session.kind.tint.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [1.5, 1])).frame(width: 6, height: 6)
        case .run: Circle().fill(KXColor.run).frame(width: 6, height: 6)
        case .lift: Circle().fill(KXColor.lift).frame(width: 6, height: 6)
        }
    }

    private func dayLabel(_ day: Date, entries: [Entry], isRace: Bool) -> String {
        var text = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if isRace { text += ", race day" }
        if entries.isEmpty { return text + ", nothing planned" }
        return text + ", " + entries.map(title).joined(separator: ", ")
    }

    private var legend: some View {
        HStack(spacing: KXSpacing.md) {
            legendItem(Circle().fill(KXColor.run), "Run")
            legendItem(Circle().fill(KXColor.lift), "Gym")
            legendItem(Circle().stroke(KXColor.inkSecondary, lineWidth: 1.5), "To do")
            legendItem(Circle().fill(KXColor.inkSecondary), "Done")
        }
        .font(KXFont.caption)
        .foregroundStyle(KXColor.inkSecondary)
        .accessibilityHidden(true)
    }

    private func legendItem(_ shape: some View, _ label: String) -> some View {
        HStack(spacing: 4) {
            shape.frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: Day list

    private func dayList(_ entries: [Entry], outline: PlanOutline?, eventDay: Date?) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(KXFont.custom(.condensedBold, 22, relativeTo: .title3))
                    .textCase(.uppercase)
                    .foregroundStyle(KXColor.ink)
                if let weekText = weekText(for: selected, outline: outline) {
                    Text(weekText).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }
            }
            if let eventDay, calendar.isDate(eventDay, inSameDayAs: selected) {
                Label("Race day", systemImage: "flag.checkered")
                    .font(KXFont.bodyEmphasis)
                    .foregroundStyle(KXColor.ink)
                    .kxCard(.tinted)
            }
            if entries.isEmpty {
                Text(selected < calendar.startOfDay(for: .now) ? "Nothing recorded." : "Nothing planned. A rest day.")
                    .font(KXFont.callout)
                    .foregroundStyle(KXColor.inkSecondary)
                    .kxCard(.tinted)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in row(entry) }
        }
    }

    /// "Week 3 of 12 · Build" when the day is in the plan.
    private func weekText(for day: Date, outline: PlanOutline?) -> String? {
        guard let outline, let index = outline.weekIndex(containing: day, calendar: calendar) else { return nil }
        let week = outline.weeks[index]
        return "Week \(index + 1) of \(outline.weeks.count) · \(week.phase.displayName)\(week.isRecoveryWeek ? " · easier week" : "")"
    }

    private func title(_ entry: Entry) -> String {
        switch entry {
        case .planned(let s): return s.title
        case .preview(let s): return s.title
        case .run(let r): return r.title.isEmpty ? "Run" : r.title
        case .lift(let l): return l.title.isEmpty ? "Gym session" : l.title
        }
    }

    private func row(_ entry: Entry) -> some View {
        let symbol: String, tint: Color, detail: String, status: String?
        switch entry {
        case .planned(let s):
            symbol = s.kind.symbolName
            tint = s.kind.tint
            detail = sessionDetail(minutes: s.plannedDurationMinutes, meters: s.estimatedDistanceMeters)
            switch s.status {
            case .completed: status = "Done"
            case .skipped: status = "Skipped"
            default: status = nil
            }
        case .preview(let s):
            symbol = s.kind.symbolName
            tint = s.kind.tint
            detail = sessionDetail(minutes: s.plannedDurationMinutes, meters: s.estimatedDistanceMeters)
            status = "Preview"
        case .run(let r):
            symbol = "figure.run"
            tint = KXColor.run
            detail = "\(format.distance(r.distanceMeters)) · \(Units.formatMinutesSeconds(r.durationSeconds))"
            status = "Done"
        case .lift(let l):
            symbol = "dumbbell"
            tint = KXColor.lift
            detail = "\(Int((l.durationSeconds / 60).rounded())) min"
            status = "Done"
        }
        return HStack(spacing: KXSpacing.md) {
            Button { open(entry) } label: {
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(entry)).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                        Text(detail).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    if let status {
                        KXChip(text: status, variant: status == "Done" ? .secondary : .outlined)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPreview(entry))
            if case .planned(let session) = entry, session.status == .planned || session.status == .swapped {
                Menu {
                    Button { openSession = session } label: { Label("Details", systemImage: "info.circle") }
                    if calendar.isDateInToday(session.date) {
                        Button {
                            dismiss()
                            router.startPlanned(session, in: context)
                        } label: { Label("Start", systemImage: "play.fill") }
                    }
                    if session.status == .planned {
                        Button { actionSession = session } label: { Label("Move, swap or skip", systemImage: "arrow.left.arrow.right") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(session.title)")
            }
        }
        .kxCard(padding: KXSpacing.md)
        .accessibilityElement(children: .contain)
    }

    private func isPreview(_ entry: Entry) -> Bool {
        if case .preview = entry { return true }
        return false
    }

    private func sessionDetail(minutes: Double, meters: Double?) -> String {
        var parts = ["\(Int(minutes.rounded())) min"]
        if let meters, meters > 0 { parts.append(format.distance(meters)) }
        return parts.joined(separator: " · ")
    }

    /// Done planned sessions open what you did; others open the plan's details.
    private func open(_ entry: Entry) {
        switch entry {
        case .planned(let session):
            if session.status == .completed {
                if let run = runs.first(where: { $0.plannedSessionId == session.id }) { openRun = run; return }
                if let lift = lifts.first(where: { $0.plannedSessionId == session.id }) { openLift = lift; return }
            }
            openSession = session
        case .preview: break
        case .run(let run): openRun = run
        case .lift(let lift): openLift = lift
        }
    }
}

/// The calendar in a sheet with its own navigation, opened from Today and the Plan tab.
struct CalendarSheet: View {
    var body: some View {
        NavigationStack { TrainingCalendarView() }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
