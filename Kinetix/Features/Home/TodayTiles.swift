import SwiftUI
import TrainingEngine

/// This week as a compact row: a ring of sessions done, what's next and the running so far,
/// with Calendar and Rearrange underneath.
struct ThisWeekTile: View {
    let days: [DashboardData.WeekDay]
    var actualRunMeters: Double = 0
    var plannedRunMeters: Double = 0
    var format = DisplayFormat(units: UnitPreference.stored)
    let onOpen: () -> Void
    @State private var rearranging = false

    private var sessions: [PlannedSessionModel] { days.flatMap(\.sessions) }
    private var done: Int { sessions.filter { $0.status == .completed }.count }
    private var total: Int { sessions.filter { $0.status != .skipped }.count }

    private var next: PlannedSessionModel? {
        let now = Date.now
        let today = Calendar.kinetix.startOfDay(for: now)
        return sessions
            .filter { ($0.status == .planned || $0.status == .swapped) && $0.date >= today }
            .sorted { $0.date < $1.date }
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Button(action: onOpen) {
                HStack(spacing: KXSpacing.md) {
                    ring
                    VStack(alignment: .leading, spacing: 2) {
                        KXOverline("This week")
                        nextText
                        if plannedRunMeters > 0 {
                            Text("\(format.distance(actualRunMeters)) of \(format.distance(plannedRunMeters, decimals: 0)) run")
                                .font(KXFont.caption)
                                .foregroundStyle(KXColor.inkSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week: \(done) of \(total) sessions done" + (next.map { ". Next: \($0.title)" } ?? ""))
            .accessibilityHint("Opens your calendar")
            .accessibilityIdentifier("today.weekTile")
            Divider().overlay(KXColor.border)
            HStack(spacing: KXSpacing.lg) {
                Button("Calendar", action: onOpen)
                Button("Rearrange") { rearranging = true }
                    .accessibilityIdentifier("today.rearrange")
                Spacer(minLength: 0)
            }
            .font(KXFont.callout)
            .foregroundStyle(KXColor.inkSecondary)
        }
        .padding(.vertical, KXSpacing.md)
        .padding(.leading, KXSpacing.lg)
        .padding(.trailing, KXSpacing.md)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .sheet(isPresented: $rearranging) { WeekRearrangeView() }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(KXColor.surfaceTint, lineWidth: 6)
            Circle()
                .trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                .stroke(KXColor.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)")
                .font(KXFont.number(17, relativeTo: .headline))
                .foregroundStyle(KXColor.ink)
        }
        .frame(width: 52, height: 52)
    }

    @ViewBuilder private var nextText: some View {
        if let next {
            let day = Calendar.kinetix.isDateInToday(next.date) ? "today" : next.date.formatted(.dateTime.weekday(.abbreviated))
            (Text("Next: ").foregroundColor(KXColor.inkSecondary) + Text(next.title).bold().foregroundColor(KXColor.ink)
                + Text(" · \(day)").foregroundColor(KXColor.inkSecondary))
                .font(KXFont.callout)
                .lineLimit(1)
        } else {
            Text(total > 0 ? "All done this week" : "Nothing planned")
                .font(KXFont.bodyEmphasis)
                .foregroundStyle(total > 0 ? KXColor.success : KXColor.inkSecondary)
        }
    }
}
