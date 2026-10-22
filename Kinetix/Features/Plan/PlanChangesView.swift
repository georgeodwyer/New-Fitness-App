import SwiftUI
import SwiftData
import TrainingEngine

/// "What changed and why": every automatic change to the plan as a before → after card
/// with the reason and the numbers that triggered it, newest first, grouped by day.
struct PlanChangesView: View {
    let changes: [PlanChangeModel]
    var emptyMessage = "When Kinetix moves, eases or swaps a session (after a skip, a training-load spike or a low score) you'll see exactly what changed and why here."

    @Query(filter: #Predicate<UserProfileModel> { $0.deletedAt == nil }) private var profiles: [UserProfileModel]
    private var units: UnitSystem { profiles.first?.units ?? UnitPreference.stored }

    private var groups: [(day: Date, changes: [PlanChangeModel])] {
        let calendar = Calendar.kinetix
        let grouped = Dictionary(grouping: changes.filter { !$0.isSoftDeleted }) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.xl) {
                if groups.isEmpty {
                    KXEmptyState(symbol: "arrow.triangle.2.circlepath", title: "No changes yet", message: emptyMessage)
                        .kxCard()
                }
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: KXSpacing.md) {
                        KXOverline(dayTitle(group.day))
                        ForEach(group.changes) { change in
                            PlanChangeCard(change: change, units: units)
                        }
                    }
                }
            }
            .padding(KXSpacing.screenMargin)
        }
        .background(KXColor.background.ignoresSafeArea())
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.kinetix
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// One change: what triggered it, the session before and after, and the reason.
struct PlanChangeCard: View {
    let change: PlanChangeModel
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                KXChip(text: change.cause.title, systemImage: change.cause.symbol, variant: change.cause.chipVariant)
                Spacer()
                Text(change.createdAt, format: .dateTime.hour().minute())
                    .font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
            }
            Text(change.summary)
                .font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let before = change.before, let after = change.after {
                sessionComparison(before: before, after: after)
                let fields = PlanChangeDiff.changes(from: before, to: after, units: units)
                if !fields.isEmpty {
                    VStack(spacing: KXSpacing.xs) {
                        ForEach(fields) { field in fieldRow(field) }
                    }
                }
            }

            if !change.triggers.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    KXOverline("What triggered it")
                    ForEach(change.triggers) { trigger in triggerRow(trigger) }
                }
            }
        }
        .kxCard()
    }

    /// Before and after sessions side by side, the old one struck through.
    private func sessionComparison(before: SessionSnapshot, after: SessionSnapshot) -> some View {
        HStack(spacing: KXSpacing.sm) {
            sessionBadge(before, crossedOut: before.title != after.title || after.status == .skipped)
            Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(KXColor.inkTertiary)
                .accessibilityHidden(true)
            sessionBadge(after, crossedOut: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Before: \(before.title). After: \(after.title)\(after.status == .skipped ? ", skipped" : "").")
    }

    private func sessionBadge(_ snapshot: SessionSnapshot, crossedOut: Bool) -> some View {
        HStack(spacing: KXSpacing.xs) {
            Image(systemName: snapshot.kind.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(snapshot.kind.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.title)
                    .font(KXFont.captionEmphasis)
                    .foregroundStyle(crossedOut ? KXColor.inkSecondary : KXColor.ink)
                    .strikethrough(crossedOut)
                    .lineLimit(1)
                Text(snapshot.date.formatted(.dateTime.weekday(.abbreviated)) + " · \(Int(snapshot.durationMinutes.rounded())) min")
                    .font(.caption2).foregroundStyle(KXColor.inkSecondary)
            }
        }
        .padding(.horizontal, KXSpacing.sm)
        .padding(.vertical, KXSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
    }

    private func fieldRow(_ field: FieldChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.sm) {
            Text(field.label).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                .frame(width: 92, alignment: .leading)
            Text(field.before).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary).strikethrough()
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(KXColor.inkTertiary)
            Text(field.after).font(KXFont.captionEmphasis).foregroundStyle(KXColor.ink)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(field.label) changed from \(field.before) to \(field.after)")
    }

    private func triggerRow(_ trigger: ChangeTrigger) -> some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: trigger.symbol)
                .font(.caption)
                .foregroundStyle(KXColor.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(trigger.label).font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
            Text(trigger.value).font(KXFont.captionEmphasis.monospacedDigit()).foregroundStyle(KXColor.ink)
            if let detail = trigger.detail {
                Text(detail).font(.caption2).foregroundStyle(KXColor.inkTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension ChangeCause {
    var title: String {
        switch self {
        case .skipped: return "You skipped a session"
        case .swapped: return "You swapped a session"
        case .highLoad: return "Training load spike"
        case .poorRecovery: return "Your score"
        case .lowRecovery: return "Recovery"
        case .other: return "Plan update"
        }
    }

    var symbol: String {
        switch self {
        case .skipped: return "forward.end"
        case .swapped: return "arrow.left.arrow.right"
        case .highLoad: return "exclamationmark.triangle.fill"
        case .poorRecovery: return "bed.double"
        case .lowRecovery: return "battery.25percent"
        case .other: return "info.circle"
        }
    }

    var chipVariant: KXChip.Variant {
        switch self {
        case .highLoad, .poorRecovery, .lowRecovery: return .warning
        case .swapped: return .secondary
        case .skipped, .other: return .outlined
        }
    }
}
