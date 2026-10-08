import SwiftUI
import SwiftData
import TrainingEngine

/// The upcoming plan, grouped by day.
struct PlanView: View {
    @Query(sort: \PlannedSessionModel.date) private var sessions: [PlannedSessionModel]

    private struct DayGroup: Identifiable {
        let day: Date
        let sessions: [PlannedSessionModel]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let upcoming = sessions.filter { !$0.isSoftDeleted && $0.date >= today }
        let grouped = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            DayGroup(day: day, sessions: grouped[day, default: []].sorted { $0.slot == .morning && $1.slot == .evening })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                KXScreenHeader(title: "Training Plan")
                if days.isEmpty {
                    Text("No sessions planned yet.")
                        .font(KXFont.callout)
                        .foregroundStyle(KXColor.inkSecondary)
                        .kxCard(.tinted)
                }
                ForEach(days) { entry in
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        KXOverline(entry.day.formatted(.dateTime.weekday(.wide).day().month()))
                        ForEach(entry.sessions) { session in
                            HStack(spacing: KXSpacing.md) {
                                Image(systemName: session.kind.symbolName)
                                    .foregroundStyle(session.kind.discipline == .run ? KXColor.accent : KXColor.slate)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                    Text(session.kind.displayName).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                    Text("\(Int(session.plannedDurationMinutes)) min").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                }
                                Spacer()
                                if session.isKey {
                                    KXChip(text: "Key", systemImage: "star.fill", variant: .secondary)
                                }
                            }
                            .kxCard(padding: KXSpacing.md)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
    }
}
