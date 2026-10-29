import SwiftUI
import SwiftData
import TrainingEngine

/// This week or next as seven days: press and hold a session and drag it to another day.
/// Dropping it on a day with a session swaps the two. Kinetix says if it puts hard sessions
/// too close together, but lets it happen.
struct WeekRearrangeView: View {
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<TrainingPlanModel> { $0.isActive }) private var plans: [TrainingPlanModel]
    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 0 = this week, 1 = next week.
    @State var weekOffset = 1
    @State private var message: String?
    @State private var warning: String?
    @State private var targeted: Date?

    private let calendar = Calendar.kinetix
    private var today: Date { calendar.startOfDay(for: .now) }

    private var days: [Date] {
        let monday = calendar.startOfISOWeek(for: today)
        let start = calendar.date(byAdding: .day, value: 7 * weekOffset, to: monday) ?? monday
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func sessions(on day: Date) -> [PlannedSessionModel] {
        let activeID = plans.first?.id
        return sessions.filter {
            !$0.isSoftDeleted && $0.plan?.id == activeID && calendar.isDate($0.date, inSameDayAs: day)
        }
        .sorted { $0.slot == .morning && $1.slot == .evening }
    }

    private func canMove(_ session: PlannedSessionModel) -> Bool {
        (session.status == .planned || session.status == .swapped) && session.date >= today
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    Picker("Week", selection: $weekOffset) {
                        Text("This week").tag(0)
                        Text("Next week").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Text("Press and hold a session, then drag it to another day. Drop it on a day that has a session to swap them.")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.ink)
                            .symbolRenderingMode(.multicolor)
                            .fixedSize(horizontal: false, vertical: true)
                            .kxCard(.tinted)
                    } else if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(KXFont.caption)
                            .foregroundStyle(KXColor.ink)
                            .symbolRenderingMode(.multicolor)
                            .fixedSize(horizontal: false, vertical: true)
                            .kxCard(.tinted)
                    }
                    ForEach(days, id: \.self) { day in dayRow(day) }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Rearrange week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: weekOffset) { _, _ in message = nil; warning = nil }
        }
        .tint(KXColor.accent)
    }

    private func dayRow(_ day: Date) -> some View {
        let items = sessions(on: day)
        let isPast = day < today
        let isTargeted = targeted == day
        return VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(isPast ? KXColor.inkTertiary : KXColor.inkSecondary)
                if calendar.isDate(day, inSameDayAs: today) {
                    KXChip(text: "Today", variant: .primary)
                }
                Spacer()
            }
            if items.isEmpty {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "moon.zzz").foregroundStyle(KXColor.inkTertiary).frame(width: 20)
                    Text(isTargeted ? "Drop here" : "Rest day").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                    Spacer()
                }
                .padding(.vertical, KXSpacing.xs)
            }
            ForEach(items) { session in chip(session) }
        }
        .padding(KXSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isTargeted ? KXColor.accentSoft : KXColor.surface,
                    in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .strokeBorder(isTargeted ? KXColor.accent : .clear, lineWidth: 1.5)
        }
        .opacity(isPast ? 0.6 : 1)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            return drop(id, on: day)
        } isTargeted: { over in
            if over { targeted = day } else if targeted == day { targeted = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide)))
    }

    private func chip(_ session: PlannedSessionModel) -> some View {
        let movable = canMove(session)
        return HStack(spacing: KXSpacing.sm) {
            Image(systemName: session.kind.symbolName)
                .foregroundStyle(session.kind.tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                Text(detail(session)).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: KXSpacing.xs)
            if session.status == .completed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(KXColor.success)
            } else if session.status == .skipped {
                Text("Skipped").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            } else if movable {
                Image(systemName: "line.3.horizontal").foregroundStyle(KXColor.inkTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, KXSpacing.sm)
        .padding(.vertical, KXSpacing.xs)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .opacity(movable || session.status == .completed ? 1 : 0.6)
        .modifier(DraggableSession(session: session, enabled: movable))
        .accessibilityElement(children: .combine)
        .accessibilityHint(movable ? "Press and hold, then drag to another day" : "")
    }

    private func detail(_ session: PlannedSessionModel) -> String {
        var parts = ["\(Int(session.plannedDurationMinutes)) min"]
        if let meters = session.estimatedDistanceMeters {
            parts.append(DisplayFormat(units: profiles.first?.units ?? UnitPreference.stored).distance(meters))
        }
        if session.slot == .evening { parts.append("evening") }
        return parts.joined(separator: " · ")
    }

    private func drop(_ id: UUID, on day: Date) -> Bool {
        targeted = nil
        guard let session = sessions.first(where: { $0.id == id }), let profile = profiles.first?.profile else { return false }
        guard canMove(session) else {
            message = nil
            warning = "Only sessions from today on that aren't done yet can be moved."
            return false
        }
        guard day >= today else {
            message = nil
            warning = "That day has passed. Pick today or a day ahead."
            return false
        }
        guard let result = withAnimation(.easeInOut(duration: 0.25), {
            BalanceService.drop(session, on: day, profile: profile, in: context)
        }) else { return false }
        warning = result.warning
        message = result.explanations.first
        return true
    }
}

/// Drag only the sessions that can move.
private struct DraggableSession: ViewModifier {
    let session: PlannedSessionModel
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(session.id.uuidString) {
                Label(session.title, systemImage: session.kind.symbolName)
                    .font(KXFont.bodyEmphasis)
                    .padding(KXSpacing.md)
                    .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md))
            }
        } else {
            content
        }
    }
}
