import SwiftUI
import SwiftData
import TrainingEngine

/// Record → Gym: resume, start an empty workout, or start/edit a saved one.
struct GymSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<GymTemplateModel> { $0.deletedAt == nil }, sort: \GymTemplateModel.createdAt, order: .reverse)
    private var templates: [GymTemplateModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isRecorded && !$0.isFinished && $0.deletedAt == nil })
    private var unfinished: [StrengthLogModel]

    @State private var startRequest: GymStartRequest?

    /// Most recently used first.
    private var sortedTemplates: [GymTemplateModel] {
        templates.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                if let log = unfinished.max(by: { $0.startedAt < $1.startedAt }) {
                    resumeCard(log)
                }

                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Button {
                        startRequest = GymStartRequest(title: "Gym workout", items: [])
                    } label: {
                        Label("Start an empty workout", systemImage: "play.fill")
                    }
                    .buttonStyle(.kx(.primary, fullWidth: true))
                    .accessibilityIdentifier("gym.startEmpty")
                    Text("Add exercises as you go. Each one fills in with what you lifted last time.")
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                }

                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    KXSectionHeader("My gym workouts", subtitle: templates.isEmpty ? nil : "Tap to start or edit")
                    if sortedTemplates.isEmpty {
                        KXEmptyState(symbol: "bookmark", title: "No saved workouts yet",
                                     message: "Build one (say \u{201C}Push day\u{201D}) to start it with one tap next time.")
                    }
                    ForEach(sortedTemplates) { template in
                        NavigationLink {
                            GymTemplateEditorView(template: template)
                        } label: {
                            templateRow(template)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                startRequest = GymStartRequest(title: template.name, items: template.items, templateId: template.id)
                            } label: {
                                Label("Start", systemImage: "play")
                            }
                            Button(role: .destructive) {
                                template.softDelete()
                                try? context.save()
                                SyncService.shared.requestSync()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    NavigationLink {
                        GymTemplateEditorView(template: nil)
                    } label: {
                        Label("New workout", systemImage: "plus")
                    }
                    .buttonStyle(.kx(.secondary, fullWidth: true))
                    .accessibilityIdentifier("gym.newTemplate")
                }
                .kxCard()
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.inline)
        .gymStartFlow($startRequest)
    }

    private func resumeCard(_ log: StrengthLogModel) -> some View {
        HStack(spacing: KXSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                KXOverline("In progress", color: KXColor.lift)
                Text(log.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text("Started \(log.startedAt.formatted(.relative(presentation: .named)))")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
            Spacer()
            Button("Resume") {
                router.start(ActiveSession(id: log.id, kind: .strength(.fullBody), title: log.title, strengthLogId: log.id))
            }
            .buttonStyle(.kx(.primary))
            .accessibilityIdentifier("gym.resume")
        }
        .kxCard(.raised)
    }

    private func templateRow(_ template: GymTemplateModel) -> some View {
        let items = template.items
        return HStack(spacing: KXSpacing.md) {
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(KXColor.lift)
                .frame(width: 36, height: 36)
                .background(KXColor.lift.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                Text(GymTemplate.summary(items)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                Text(items.map(\.name).joined(separator: ", "))
                    .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary).accessibilityHidden(true)
        }
        .padding(.vertical, KXSpacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Starting a workout

/// A tap on "Start": a fresh id each time so repeated taps always register.
struct GymStartRequest: Equatable {
    let id = UUID()
    var title: String
    var items: [GymTemplateItem]
    var templateId: UUID? = nil
}

extension View {
    /// Shows the health notice (first time) and the "is this your planned session?" question,
    /// then opens the workout.
    func gymStartFlow(_ request: Binding<GymStartRequest?>) -> some View {
        modifier(GymStartFlow(request: request))
    }
}

private struct GymStartFlow: ViewModifier {
    @Binding var request: GymStartRequest?

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @AppStorage(HealthNotice.key) private var healthNoticeAccepted = false
    @State private var showHealthNotice = false
    @State private var askAboutPlan = false

    /// Gym sessions from this week's plan still to do: today's first, then the rest of the
    /// week, then any missed earlier in the week (at most three).
    private var plannedThisWeek: [PlannedSessionModel] {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: .now)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let open = sessions.filter {
            !$0.isSoftDeleted && week.contains($0.date) && $0.kind.discipline == .strength
                && ($0.status == .planned || $0.status == .swapped) && ($0.plan?.isActive ?? true)
        }
        func rank(_ session: PlannedSessionModel) -> (Int, Date) {
            let day = calendar.startOfDay(for: session.date)
            return (day == today ? 0 : day > today ? 1 : 2, session.date)
        }
        return Array(open.sorted { rank($0) < rank($1) }.prefix(3))
    }

    private var plannedToday: PlannedSessionModel? {
        plannedThisWeek.first.flatMap { Calendar.kinetix.isDateInToday($0.date) ? $0 : nil }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, newValue in
                guard newValue != nil else { return }
                if healthNoticeAccepted { proceed() } else { showHealthNotice = true }
            }
            .sheet(isPresented: $showHealthNotice) {
                HealthNoticeSheet {
                    healthNoticeAccepted = true
                    showHealthNotice = false
                    // Let the sheet close before the workout opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proceed() }
                }
            }
            .confirmationDialog(planQuestion, isPresented: $askAboutPlan, titleVisibility: .visible) {
                ForEach(plannedThisWeek) { planned in
                    Button("Yes, count it as my \(planned.title.lowercased())\(dayLabel(planned))") { start(linking: planned) }
                }
                Button("No, it's an extra session") { start(linking: nil) }
                if let planned = plannedToday {
                    Button("Do the planned \(planned.title.lowercased()) instead") {
                        request = nil
                        router.startPlanned(planned, in: context)
                    }
                }
            } message: {
                if let planned = plannedToday {
                    Text("Your plan has \(planned.title.lowercased()) (\(planned.summary)) today. If this workout replaces it, it's ticked off; if not, both count towards your training load.")
                } else {
                    Text("If this workout replaces one of this week's gym sessions, it's ticked off and moved to today. If not, it's an extra session; both count towards your training load.")
                }
            }
    }

    /// " (Thu)" for a session on another day.
    private func dayLabel(_ planned: PlannedSessionModel) -> String {
        Calendar.kinetix.isDateInToday(planned.date) ? "" : " (\(planned.date.formatted(.dateTime.weekday(.abbreviated))))"
    }

    private var planQuestion: String {
        if let planned = plannedToday { return "You have \(planned.title.lowercased()) planned today. Is this it?" }
        return "Does this count towards your plan?"
    }

    private func proceed() {
        guard request != nil else { return }
        if plannedThisWeek.isEmpty { start(linking: nil) } else { askAboutPlan = true }
    }

    private func start(linking planned: PlannedSessionModel?) {
        guard let request else { return }
        // A session from another day done today moves to today, so the week shows what happened.
        if let planned, !Calendar.kinetix.isDateInToday(planned.date) {
            let calendar = Calendar.kinetix
            let time = planned.date.timeIntervalSince(calendar.startOfDay(for: planned.date))
            planned.date = calendar.startOfDay(for: .now).addingTimeInterval(time)
            planned.touch()
        }
        if let templateId = request.templateId,
           let template = try? context.fetch(FetchDescriptor<GymTemplateModel>(predicate: #Predicate { $0.id == templateId })).first {
            template.lastUsedAt = .now
            template.touch()
        }
        let log = GymService.start(title: request.title, items: request.items, linkedPlanned: planned,
                                   templateId: request.templateId, in: context)
        self.request = nil
        router.start(ActiveSession(id: log.id, kind: .strength(.fullBody), title: log.title, strengthLogId: log.id))
    }
}
