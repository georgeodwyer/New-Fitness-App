import SwiftUI
import TrainingEngine

/// Tile height: about square on an iPhone (two tiles side by side), taller with large text.
private let tileMinHeight: CGFloat = 172

/// Today's session as a square tile: what it is, how long, and Start. On a day with two
/// sessions it shows one at a time ("1 of 2" switches).
struct TodaySessionTile: View {
    let sessions: [PlannedSessionModel]
    /// When the plan hasn't started yet.
    let planStart: Date?
    @Binding var shownIndex: Int?
    let onStart: (PlannedSessionModel) -> Void
    let onDetails: (PlannedSessionModel) -> Void
    let onActions: (PlannedSessionModel) -> Void

    /// The session showing: the one chosen, else the first not yet done.
    private var index: Int? {
        guard !sessions.isEmpty else { return nil }
        if let shownIndex, sessions.indices.contains(shownIndex) { return shownIndex }
        return sessions.firstIndex { $0.status == .planned || $0.status == .swapped } ?? 0
    }

    var body: some View {
        Group {
            if let index { sessionTile(sessions[index], index: index) } else { restTile }
        }
        .frame(maxWidth: .infinity, minHeight: tileMinHeight, alignment: .topLeading)
        .kxCard(padding: KXSpacing.md)
    }

    private func sessionTile(_ session: PlannedSessionModel, index: Int) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .center) {
                KXOverline(overline(session), color: KXColor.accent)
                Spacer(minLength: 0)
                Menu {
                    Button { onDetails(session) } label: { Label("Details", systemImage: "info.circle") }
                    if session.status == .planned {
                        Button { onActions(session) } label: { Label("Skip, swap or move", systemImage: "arrow.left.arrow.right") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KXColor.inkSecondary)
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(session.title)")
            }
            Button { onDetails(session) } label: {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    Image(systemName: session.kind.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(session.kind.tint)
                        .frame(width: 36, height: 36)
                        .background(KXColor.surfaceTint, in: Circle())
                    Text(session.title)
                        .font(KXFont.headline)
                        .foregroundStyle(KXColor.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(Int(session.plannedDurationMinutes)) min · \(session.summary)")
                        .font(KXFont.caption)
                        .foregroundStyle(KXColor.inkSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            HStack(spacing: KXSpacing.sm) {
                switch session.status {
                case .completed:
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(KXFont.captionEmphasis).foregroundStyle(KXColor.success)
                case .skipped:
                    Label("Skipped", systemImage: "xmark.circle")
                        .font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                default:
                    if canStart(session) {
                        Button("Start") { onStart(session) }
                            .buttonStyle(.kx(.primary))
                            .accessibilityLabel("Start \(session.title)")
                    }
                }
                Spacer(minLength: 0)
                if sessions.count > 1 {
                    Button {
                        shownIndex = (index + 1) % sessions.count
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(index + 1) of \(sessions.count)")
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.accent)
                    }
                    .accessibilityLabel("Show the next of today's \(sessions.count) sessions")
                }
            }
        }
        .accessibilityIdentifier("today.sessionTile")
    }

    private var restTile: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXOverline("Today", color: KXColor.accent)
            Image(systemName: planStart == nil ? "bed.double.fill" : "calendar")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KXColor.teal)
                .frame(width: 36, height: 36)
                .background(KXColor.surfaceTint, in: Circle())
            if let planStart {
                Text("Plan starts \(planStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text("An easy run, a walk or rest until then.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            } else {
                Text("Rest day").font(KXFont.headline).foregroundStyle(KXColor.ink)
                Text("Recovery is when the training sinks in.")
                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func overline(_ session: PlannedSessionModel) -> String {
        var text = sessions.count > 1 ? (session.slot == .morning ? "Morning" : "Evening") : "Today"
        if session.status == .swapped { text += " · Swapped" }
        return text
    }

    private func canStart(_ session: PlannedSessionModel) -> Bool {
        session.kind.discipline == .run || session.kind.discipline == .strength
    }
}

/// This week as a square tile: sessions done, a dot per day and what's next. Opens the plan.
struct ThisWeekTile: View {
    let days: [DashboardData.WeekDay]
    let onOpen: () -> Void

    private var sessions: [PlannedSessionModel] { days.flatMap(\.sessions) }
    private var done: Int { sessions.filter { $0.status == .completed }.count }
    private var total: Int { sessions.filter { $0.status != .skipped }.count }
    private var doubleDays: Int { days.filter { $0.sessions.filter { $0.status != .skipped }.count >= 2 }.count }

    private var next: PlannedSessionModel? {
        let today = Calendar.kinetix.startOfDay(for: .now)
        return sessions
            .filter { ($0.status == .planned || $0.status == .swapped) && $0.date >= today }
            .sorted { $0.date < $1.date }
            .first
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack {
                    KXOverline("This week", color: KXColor.accent)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.inkTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xs) {
                    Text("\(done)").font(KXFont.metric).foregroundStyle(KXColor.ink)
                    Text("of \(total) done").font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                HStack(spacing: 0) {
                    ForEach(days) { day in dayDot(day).frame(maxWidth: .infinity) }
                }
                Spacer(minLength: 0)
                if let next {
                    Text("Next: \(next.title)")
                        .font(KXFont.captionEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                    Text(next.date.formatted(.dateTime.weekday(.wide)))
                        .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                } else if total > 0 {
                    Text("All done this week").font(KXFont.captionEmphasis).foregroundStyle(KXColor.success)
                }
            }
            .frame(maxWidth: .infinity, minHeight: tileMinHeight, alignment: .topLeading)
            .kxCard(padding: KXSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(done) of \(total) sessions done" + (doubleDays > 0 ? ", \(doubleDays) double-session day\(doubleDays == 1 ? "" : "s")" : "") + (next.map { ". Next: \($0.title)" } ?? ""))
        .accessibilityHint("Opens your calendar")
        .accessibilityIdentifier("today.weekTile")
    }

    /// Filled when the day's sessions are done, a ring when still to do, faint for rest days;
    /// a blue dot when there are two sessions.
    private func dayDot(_ day: DashboardData.WeekDay) -> some View {
        let active = day.sessions.filter { $0.status != .skipped }
        let allDone = !active.isEmpty && active.allSatisfy { $0.status == .completed }
        return VStack(spacing: 3) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? KXColor.accent : KXColor.inkTertiary)
            ZStack {
                if active.isEmpty {
                    Circle().fill(KXColor.border).frame(width: 6, height: 6)
                } else if allDone {
                    Circle().fill(KXColor.accent).frame(width: 12, height: 12)
                } else {
                    Circle().stroke(active.first?.kind.tint ?? KXColor.accent, lineWidth: 2).frame(width: 12, height: 12)
                }
            }
            .frame(height: 14)
            .overlay(alignment: .topTrailing) {
                // Blue dot: two sessions that day.
                if active.count >= 2 {
                    Circle()
                        .fill(KXColor.doubleSession)
                        .overlay(Circle().stroke(KXColor.surface, lineWidth: 1))
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -2)
                }
            }
        }
    }
}
