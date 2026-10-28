import SwiftUI
import TrainingEngine

/// This week, full width: sessions done, a ring for each day (full when that day's done),
/// and what's next. Opens the calendar.
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
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    KXOverline("This week")
                    Spacer(minLength: KXSpacing.sm)
                    (Text("\(done)").font(KXFont.custom(.bold, 13, relativeTo: .caption)).foregroundColor(KXColor.ink)
                        + Text(" of \(total) done").font(KXFont.caption).foregroundColor(KXColor.inkSecondary))
                }
                HStack(spacing: 0) {
                    ForEach(days) { day in dayRing(day).frame(maxWidth: .infinity) }
                }
                Divider().overlay(KXColor.border)
                HStack(spacing: KXSpacing.md) {
                    VStack(alignment: .leading, spacing: 1) {
                        KXOverline("Next")
                        if let next {
                            Text("\(next.title) · \(next.date.formatted(.dateTime.weekday(.wide)))")
                                .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink).lineLimit(1)
                        } else {
                            Text(total > 0 ? "All done this week" : "Nothing planned")
                                .font(KXFont.bodyEmphasis)
                                .foregroundStyle(total > 0 ? KXColor.success : KXColor.inkSecondary)
                        }
                    }
                    Spacer(minLength: KXSpacing.sm)
                    Label("Calendar", systemImage: "calendar")
                        .font(KXFont.captionEmphasis)
                        .foregroundStyle(KXColor.ink)
                        .padding(.horizontal, KXSpacing.md)
                        .padding(.vertical, KXSpacing.sm)
                        .background(KXColor.surfaceTint, in: Capsule())
                }
            }
            .kxCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(done) of \(total) sessions done" + (doubleDays > 0 ? ", \(doubleDays) double-session day\(doubleDays == 1 ? "" : "s")" : "") + (next.map { ". Next: \($0.title)" } ?? ""))
        .accessibilityHint("Opens your calendar")
        .accessibilityIdentifier("today.weekTile")
    }

    /// The weekday, a dot per session in its colour, and a ring with the date: full when the
    /// day's sessions are done, faint for rest days.
    private func dayRing(_ day: DashboardData.WeekDay) -> some View {
        let active = day.sessions.filter { $0.status != .skipped }
        let allDone = !active.isEmpty && active.allSatisfy { $0.status == .completed }
        return VStack(spacing: 5) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(KXFont.custom(.condensedSemiBold, 13, relativeTo: .caption2))
                .foregroundStyle(day.isToday ? KXColor.accent : KXColor.inkTertiary)
            HStack(spacing: 3) {
                ForEach(Array(active.prefix(2).enumerated()), id: \.offset) { _, session in
                    Circle().fill(session.kind.tint).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
            ZStack {
                Circle().stroke(active.isEmpty ? Color.clear : KXColor.surfaceTint, lineWidth: 3.5)
                if allDone {
                    Circle().stroke(KXColor.accent, lineWidth: 3.5)
                }
                Text(day.date.formatted(.dateTime.day()))
                    .font(KXFont.number(15, relativeTo: .caption))
                    .foregroundStyle(day.isToday ? KXColor.accent : active.isEmpty ? KXColor.inkTertiary : KXColor.ink)
            }
            .frame(width: 34, height: 34)
        }
    }
}
