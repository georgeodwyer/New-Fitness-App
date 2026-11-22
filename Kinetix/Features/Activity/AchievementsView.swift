import SwiftUI
import SwiftData
import TrainingEngine

/// Achievements: your level and this week's points (weighted towards doing your plan), the
/// month's challenges, tiered badges and the fun and hidden ones.
struct AchievementsView: View {
    let units: UnitSystem
    @Query private var runs: [RunLogModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished }) private var workouts: [StrengthLogModel]
    @Query(filter: #Predicate<PlannedSessionModel> { $0.deletedAt == nil }) private var sessions: [PlannedSessionModel]
    @Query(filter: #Predicate<RecoveryCheckInModel> { $0.deletedAt == nil }) private var checkIns: [RecoveryCheckInModel]
    @Query(filter: #Predicate<PersonalRecordModel> { $0.deletedAt == nil }) private var records: [PersonalRecordModel]
    @State private var integrations = IntegrationSettings.shared
    @State private var showPointsHelp = false

    var body: some View {
        let calendar = Calendar.kinetix
        let activities = ActivityRecords.make(runs: runs, lifts: workouts, external: integrations.loadWorkouts)
        let planned = ActivityRecords.planned(sessions.filter { $0.plan?.isActive ?? true })
        let weeks = Points.weeks(activities, planned: planned, now: .now, calendar: calendar)
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            FriendsCard()
            pointsCard(weeks, calendar: calendar)
            challengesCard(activities, planned: planned, calendar: calendar)
            badgesCard
            funBadgesCard(FunBadges.make(activities, recordDates: ActivityRecords.recordDates(records), calendar: calendar))
        }
        .sheet(isPresented: $showPointsHelp) { PointsHelpSheet() }
    }

    // MARK: Points

    private func pointsCard(_ weeks: [Points.Week], calendar: Calendar) -> some View {
        let thisWeek = weeks.last { calendar.isDate($0.start, equalTo: .now, toGranularity: .weekOfYear) }
        let recent = Array(weeks.suffix(8))
        let best = Double(recent.map(\.total).max() ?? 1)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack {
                KXSectionHeader("This week", subtitle: "Points count towards your level")
                Spacer()
                Button { showPointsHelp = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("How points work")
            }
            HStack(spacing: KXSpacing.sm) {
                pointTile("Plan", thisWeek?.planned ?? 0, KXColor.accent)
                pointTile("Full week", thisWeek?.fullWeek ?? 0, KXColor.success)
                pointTile("Streak", thisWeek?.streak ?? 0, KXColor.warning)
                pointTile("Training", thisWeek?.load ?? 0, KXColor.run)
            }
            if recent.count > 1 {
                KXOverline("Last 8 weeks")
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(recent, id: \.start) { week in
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(calendar.isDate(week.start, equalTo: .now, toGranularity: .weekOfYear) ? KXColor.accent : KXColor.accent.opacity(0.4))
                                .frame(height: max(4, 70 * Double(week.total) / max(best, 1)))
                            Text("\(week.total)").font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 90, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Points for the last \(recent.count) weeks: \(recent.map { String($0.total) }.joined(separator: ", "))")
            }
        }
        .kxCard()
    }

    private func pointTile(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(KXFont.number(22, relativeTo: .title3)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(KXFont.caption2).foregroundStyle(KXColor.inkSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KXSpacing.sm)
        .background(KXColor.surfaceTint, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Challenges

    private func challengesCard(_ activities: [ActivityRecord], planned: [PlannedRecord], calendar: Calendar) -> some View {
        let challenges = MonthlyChallenges.forMonth(containing: .now, calendar: calendar)
        let daysLeft = challenges.first.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: $0.end).day ?? 0 } ?? 0
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Monthly challenges", subtitle: "\(daysLeft) days left")
            ForEach(challenges) { challenge in
                let value = MonthlyChallenges.value(challenge, activities: activities, planned: planned, calendar: calendar)
                let done = value >= challenge.target
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: done ? "checkmark.circle.fill" : challenge.symbol)
                        .foregroundStyle(done ? KXColor.success : KXColor.accent)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(challenge.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                            Spacer()
                            Text(progressText(challenge, value: value)).font(KXFont.captionEmphasis.monospacedDigit())
                                .foregroundStyle(done ? KXColor.success : KXColor.inkSecondary)
                        }
                        ProgressView(value: min(value / max(challenge.target, 1), 1)).tint(done ? KXColor.success : KXColor.accent)
                        Text(challenge.detail).font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }

    private func progressText(_ challenge: Challenge, value: Double) -> String {
        switch challenge.metric {
        case .runKilometres: return String(format: "%.1f / %.0f km", value, challenge.target)
        case .plannedShare: return "\(Int(value))%"
        default: return "\(Int(value)) / \(Int(challenge.target))"
        }
    }

    // MARK: Tiered badges

    private var badgesCard: some View {
        let all = AchievementsCard.compute(checkIns: checkIns, runs: runs.filter { $0.isFinished && !$0.isSoftDeleted },
                                           lifts: workouts.filter { !$0.isSoftDeleted }, records: records)
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Badges", subtitle: "Bronze, silver, gold, then platinum for the top level")
            ForEach(all) { item in
                HStack(spacing: KXSpacing.md) {
                    AchievementBadge(achievement: item, size: 46)
                        .overlay(Circle().stroke(tierColor(item.tier), lineWidth: item.tier == nil ? 0 : 3))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.kind.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                            Spacer()
                            if let tier = item.tier {
                                Text(tier.displayName).font(KXFont.caption2Emphasis).foregroundStyle(tierColor(tier))
                            }
                        }
                        Text(item.earnedName.map { "Earned: \($0)" } ?? "Not earned yet")
                            .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                        if let next = item.nextName {
                            ProgressView(value: item.progress).tint(KXColor.accent)
                            Text("Next: \(next)").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .kxCard()
    }

    private func tierColor(_ tier: BadgeTier?) -> Color {
        switch tier {
        case .bronze: return Color(red: 0.76, green: 0.49, blue: 0.23)
        case .silver: return Color(red: 0.65, green: 0.69, blue: 0.73)
        case .gold: return Color(red: 0.91, green: 0.72, blue: 0.23)
        case .platinum: return Color(red: 0.50, green: 0.84, blue: 0.91)
        case nil: return .clear
        }
    }

    // MARK: Fun and hidden badges

    private func funBadgesCard(_ badges: [FunBadge]) -> some View {
        let earned = badges.filter(\.earned).count
        return VStack(alignment: .leading, spacing: KXSpacing.md) {
            KXSectionHeader("Extras", subtitle: "\(earned) of \(badges.count) found · some are secret")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: KXSpacing.sm)], spacing: KXSpacing.sm) {
                ForEach(badges) { badge in
                    let secret = badge.isHidden && !badge.earned
                    VStack(spacing: 6) {
                        Image(systemName: secret ? "questionmark" : badge.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(badge.earned ? KXColor.onAccent : KXColor.inkTertiary)
                            .frame(width: 46, height: 46)
                            .background(badge.earned ? KXColor.accent : KXColor.surfaceTint, in: Circle())
                        Text(secret ? "Secret" : badge.name).font(KXFont.captionEmphasis).foregroundStyle(KXColor.ink)
                            .multilineTextAlignment(.center).lineLimit(2)
                        Text(secret ? "Keep training" : badge.detail).font(KXFont.caption2).foregroundStyle(KXColor.inkTertiary)
                            .multilineTextAlignment(.center).lineLimit(3)
                        if !badge.earned && !secret && badge.target > 1 {
                            ProgressView(value: badge.progress).tint(KXColor.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(KXSpacing.sm)
                    .background(KXColor.surfaceTint.opacity(badge.earned ? 0 : 0.6), in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(secret ? "Secret badge, not found yet" : "\(badge.name), \(badge.earned ? "earned" : "not earned yet"). \(badge.detail)")
                }
            }
        }
        .kxCard()
    }
}

/// How points and levels work, in plain words.
private struct PointsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    Text("Points reward turning up and sticking to your plan more than doing the most.")
                        .font(KXFont.body).foregroundStyle(KXColor.ink)
                    row("checkmark.circle.fill", "+\(Points.plannedSession) for each planned session you do")
                    row("star.fill", "+\(Points.fullPlannedWeek) for a week with every planned session done")
                    row("flame.fill", "+\(Points.streakPerWeek) for each week in a row you've trained (up to \(Points.streakCap))")
                    row("bolt.heart.fill", "1 point per \(Int(Points.loadPerPoint)) training load, up to \(Points.dailyLoadCap) a day, so overdoing it doesn't win")
                    Text("Every session counts, whether Kinetix recorded it, you logged it by hand or it came from Apple Health. Your points add up to XP, and each level needs a little more than the last.")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("How points work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Image(systemName: symbol).foregroundStyle(KXColor.accent).frame(width: 24).accessibilityHidden(true)
            Text(text).font(KXFont.callout).foregroundStyle(KXColor.ink)
        }
    }
}
