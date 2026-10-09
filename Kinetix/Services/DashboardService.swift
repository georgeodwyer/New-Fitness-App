import Foundation
import SwiftData
import TrainingEngine

/// Everything the dashboard shows, computed from the database.
struct DashboardData {
    struct WeekDay: Identifiable {
        let date: Date
        let sessions: [PlannedSessionModel]
        let isToday: Bool
        let isTrainingDay: Bool
        var id: Date { date }
    }

    struct Adherence {
        var completed = 0
        var skipped = 0
        var swapped = 0
        /// Planned sessions whose day has passed without being done.
        var missed = 0
        var upcoming = 0
        /// Swaps are counted for information only; the session also sits in one of the other buckets.
        var total: Int { completed + skipped + missed + upcoming }
        /// Done (including swapped-and-done) out of sessions due so far.
        var percent: Int? {
            let due = completed + skipped + missed
            return due > 0 ? Int((Double(completed) / Double(due) * 100).rounded()) : nil
        }
    }

    var load: LoadReport
    var week: [WeekDay]
    var plannedRunMeters: Double
    var actualRunMeters: Double
    var plannedLiftVolumeKg: Double
    var actualLiftVolumeKg: Double
    var adherence: Adherence
    var todaysCheckIn: RecoveryCheckInModel?
}

@MainActor
enum DashboardService {
    static func loadEntries(runs: [RunLogModel], lifts: [StrengthLogModel]) -> [LoadEntry] {
        runs.filter { $0.isFinished && !$0.isSoftDeleted }.map { LoadEntry(date: $0.startedAt, discipline: .run, load: $0.load) }
            + lifts.filter { $0.isFinished && !$0.isSoftDeleted }.map { LoadEntry(date: $0.startedAt, discipline: .strength, load: $0.load) }
    }

    static func make(
        sessions: [PlannedSessionModel],
        runs: [RunLogModel],
        lifts: [StrengthLogModel],
        checkIns: [RecoveryCheckInModel],
        profile: AthleteProfile?,
        now: Date = .now
    ) -> DashboardData {
        let calendar = Calendar.kinetix
        let today = calendar.startOfDay(for: now)
        let monday = calendar.startOfISOWeek(for: now)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? now
        let thisWeek = sessions.filter { !$0.isSoftDeleted && $0.date >= monday && $0.date < nextMonday }
        let trainingDays = Set(profile?.trainingDays ?? [])

        let week: [DashboardData.WeekDay] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monday) else { return nil }
            let onDay = thisWeek.filter { calendar.isDate($0.date, inSameDayAs: date) }
                .sorted { $0.slot == .morning && $1.slot == .evening }
            return DashboardData.WeekDay(date: date, sessions: onDay, isToday: calendar.isDate(date, inSameDayAs: today),
                                         isTrainingDay: trainingDays.contains(calendar.weekday(of: date)))
        }

        var adherence = DashboardData.Adherence()
        for session in thisWeek {
            switch session.status {
            case .completed:
                if session.originalKindData != nil { adherence.swapped += 1 }
                adherence.completed += 1
            case .skipped: adherence.skipped += 1
            case .swapped:
                adherence.swapped += 1
                if session.date < today { adherence.missed += 1 } else { adherence.upcoming += 1 }
            case .planned:
                if session.date < today { adherence.missed += 1 } else { adherence.upcoming += 1 }
            }
        }

        let plannedRun = thisWeek.filter { $0.status != .skipped && $0.kind.discipline == .run }
            .compactMap(\.estimatedDistanceMeters).reduce(0, +)
        let weekRuns = runs.filter { $0.isFinished && !$0.isSoftDeleted && $0.startedAt >= monday && $0.startedAt < nextMonday }
        let plannedVolume = thisWeek.filter { $0.status != .skipped }.compactMap(\.strengthPrescription).reduce(0.0) { total, prescription in
            total + prescription.exercises.reduce(0.0) { $0 + Double($1.sets * $1.repRange.upper) * ($1.weightKg ?? 0) }
        }
        let weekLifts = lifts.filter { $0.isFinished && !$0.isSoftDeleted && $0.startedAt >= monday && $0.startedAt < nextMonday }

        return DashboardData(
            load: LoadModel.report(entries: loadEntries(runs: runs, lifts: lifts), today: now, calendar: calendar),
            week: week,
            plannedRunMeters: plannedRun,
            actualRunMeters: weekRuns.reduce(0) { $0 + $1.distanceMeters },
            plannedLiftVolumeKg: plannedVolume,
            actualLiftVolumeKg: weekLifts.reduce(0) { $0 + $1.volumeKg },
            adherence: adherence,
            todaysCheckIn: checkIns.first { calendar.isDate($0.date, inSameDayAs: today) && !$0.isSoftDeleted }
        )
    }
}
