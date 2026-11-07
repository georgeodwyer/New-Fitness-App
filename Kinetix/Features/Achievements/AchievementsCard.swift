import SwiftUI
import SwiftData
import TrainingEngine

/// Badges on the profile: a row of earned badges and the next one to go for. Tap for all of
/// them with their levels.
struct AchievementsCard: View {
    @Query(filter: #Predicate<RecoveryCheckInModel> { $0.deletedAt == nil }) private var checkIns: [RecoveryCheckInModel]
    @Query(filter: #Predicate<RunLogModel> { $0.isFinished && $0.deletedAt == nil }) private var runs: [RunLogModel]
    @Query(filter: #Predicate<StrengthLogModel> { $0.isFinished && $0.deletedAt == nil }) private var lifts: [StrengthLogModel]
    @Query(filter: #Predicate<PersonalRecordModel> { $0.deletedAt == nil }) private var records: [PersonalRecordModel]
    @State private var showAll = false

    private var achievements: [Achievement] {
        let countedRuns = runs.filter { !$0.usedSimulatedGPS }
        let gym = lifts.filter { !$0.isFunctional && !$0.isManual }
        let functional = lifts.filter(\.isFunctional)
        let calendar = Calendar.kinetix
        let days = (countedRuns.map(\.startedAt) + lifts.map(\.startedAt)).map { calendar.startOfDay(for: $0) }
        return Achievements.make(AchievementStats(
            checkIns: checkIns.count, runs: countedRuns.count,
            runMeters: countedRuns.reduce(0) { $0 + $1.distanceMeters } + functional.reduce(0) { $0 + $1.functionalRunMeters },
            gymSessions: gym.count, functionalWorkouts: functional.count,
            personalRecords: records.count, trainingDays: days))
    }

    var body: some View {
        let all = achievements
        let earned = all.filter { $0.level > 0 }
        // The closest next badge.
        let next = all.filter { !$0.isMaxed }.max { $0.progress < $1.progress }
        Button { showAll = true } label: {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack {
                    KXOverline("Achievements")
                    Spacer()
                    Text("\(all.reduce(0) { $0 + $1.level }) badges").font(KXFont.captionEmphasis).foregroundStyle(KXColor.inkSecondary)
                    Image(systemName: "chevron.right").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                }
                if earned.isEmpty {
                    Text("Check in, run or lift to earn your first badge.")
                        .font(KXFont.callout).foregroundStyle(KXColor.inkSecondary)
                } else {
                    HStack(spacing: KXSpacing.sm) {
                        ForEach(earned.prefix(6)) { badge in AchievementBadge(achievement: badge, size: 40) }
                    }
                }
                if let next, let name = next.nextName {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next: \(name)").font(KXFont.caption).foregroundStyle(KXColor.ink)
                        ProgressView(value: next.progress).tint(KXColor.accent)
                    }
                }
            }
            .padding(KXSpacing.md)
            .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.achievements")
        .sheet(isPresented: $showAll) { AchievementsSheet(achievements: all) }
    }
}

/// A round badge: the kind's symbol, coloured once earned, with its level.
struct AchievementBadge: View {
    let achievement: Achievement
    var size: CGFloat = 52

    var body: some View {
        let earned = achievement.level > 0
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: achievement.kind.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(earned ? KXColor.onAccent : KXColor.inkTertiary)
                .frame(width: size, height: size)
                .background(earned ? KXColor.accent : KXColor.surfaceTint, in: Circle())
            if earned {
                Text("\(achievement.level)")
                    .font(KXFont.caption2Emphasis)
                    .foregroundStyle(KXColor.ink)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(KXColor.surface, in: Circle())
                    .overlay(Circle().stroke(KXColor.accent, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(achievement.earnedName ?? "\(achievement.kind.title): not earned yet")
    }
}

/// Every kind of badge: level reached, the last earned and the next.
private struct AchievementsSheet: View {
    let achievements: [Achievement]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: KXSpacing.md) {
                    ForEach(achievements) { item in
                        HStack(spacing: KXSpacing.md) {
                            AchievementBadge(achievement: item)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.kind.title).font(KXFont.bodyEmphasis).foregroundStyle(KXColor.ink)
                                    Spacer()
                                    Text("Level \(item.level) of \(item.levelCount)").font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                }
                                Text(item.earnedName.map { "Earned: \($0)" } ?? "Not earned yet")
                                    .font(KXFont.caption).foregroundStyle(KXColor.inkSecondary)
                                if let next = item.nextName {
                                    ProgressView(value: item.progress).tint(KXColor.accent)
                                    Text("Next: \(next)").font(KXFont.caption).foregroundStyle(KXColor.inkTertiary)
                                } else {
                                    Text("All levels done").font(KXFont.captionEmphasis).foregroundStyle(KXColor.success)
                                }
                            }
                        }
                        .padding(KXSpacing.md)
                        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(KXSpacing.screenMargin)
            }
            .background(KXColor.background.ignoresSafeArea())
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
