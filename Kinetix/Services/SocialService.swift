import Foundation
import Observation
import SwiftData
import TrainingEngine
import KinetixSync

/// Friends: your username and code, and keeping what friends see up to date (sessions from the
/// last 60 days with maps trimmed 200 m at each end, weekly points and challenge progress).
/// Runs after every sync. Nothing is shared until you choose a username.
@Observable
@MainActor
final class SocialService {
    static let shared = SocialService()

    enum Keys {
        static let privateSessions = "social.privateSessions"
        static let lastShared = "social.lastShared"
    }

    private(set) var profile: SocialProfile?
    private(set) var loadedProfile = false
    /// An invite link opened before the friends screen was showing.
    var pendingCode: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var publishing = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var api: SocialAPI? {
        guard AuthService.shared.isSignedIn, let client = AuthService.shared.client else { return nil }
        return SocialAPI(client: client)
    }

    // MARK: Profile

    func loadProfile() async {
        guard let api else { profile = nil; loadedProfile = true; return }
        if let fetched = try? await api.myProfile() { profile = fetched }
        loadedProfile = true
    }

    func claim(username: String, displayName: String) async throws {
        guard let api else { throw SupabaseError.notSignedIn }
        profile = try await api.claimUsername(Username.normalised(username), displayName: displayName.trimmingCharacters(in: .whitespaces))
        defaults.removeObject(forKey: Keys.lastShared)   // share everything from the last 60 days
    }

    func setSharing(_ on: Bool) async throws {
        guard let api else { throw SupabaseError.notSignedIn }
        try await api.setSharing(on)
        profile?.sharing = on
    }

    // MARK: "Only me"

    func isPrivate(_ id: UUID) -> Bool { privateIds.contains(id.uuidString) }

    func setPrivate(_ id: UUID, _ hidden: Bool) {
        var ids = privateIds
        if hidden { ids.insert(id.uuidString) } else { ids.remove(id.uuidString) }
        defaults.set(Array(ids), forKey: Keys.privateSessions)
        guard let api, profile != nil else { return }
        Task {
            if hidden { try? await api.unshare([id]) } else { defaults.removeObject(forKey: Keys.lastShared) }
        }
    }

    private var privateIds: Set<String> { Set(defaults.stringArray(forKey: Keys.privateSessions) ?? []) }

    // MARK: Publishing

    /// Shares new and changed sessions, this and recent weeks' points, and challenge progress.
    func publish(in context: ModelContext, now: Date = .now) async {
        guard let api, !publishing else { return }
        publishing = true
        defer { publishing = false }
        if !loadedProfile || profile == nil { await loadProfile() }
        guard profile != nil else { return }
        let calendar = Calendar.kinetix
        let since = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let lastShared = defaults.object(forKey: Keys.lastShared) as? Date ?? .distantPast

        let runs = (try? context.fetch(FetchDescriptor<RunLogModel>())) ?? []
        let lifts = (try? context.fetch(FetchDescriptor<StrengthLogModel>())) ?? []
        let hidden = privateIds
        var uploads: [SharedSessionUpload] = []
        var removed: [UUID] = []
        for run in runs where run.startedAt >= since && run.updatedAt > lastShared {
            if !run.isFinished { continue }
            if run.isSoftDeleted || run.usedSimulatedGPS || hidden.contains(run.id.uuidString) { removed.append(run.id); continue }
            uploads.append(Self.upload(run))
        }
        for lift in lifts where lift.startedAt >= since && lift.updatedAt > lastShared {
            if !lift.isFinished { continue }
            if lift.isSoftDeleted || hidden.contains(lift.id.uuidString) { removed.append(lift.id); continue }
            uploads.append(Self.upload(lift))
        }
        do {
            try await api.share(uploads)
            try await api.unshare(removed)
            defaults.set(now, forKey: Keys.lastShared)
        } catch {
            return   // try again after the next sync
        }

        let (activities, planned) = ActivityRecords.all(in: context, now: now)
        let weeks = Points.weeks(activities, planned: planned, now: now, calendar: calendar).suffix(4)
        try? await api.savePoints(weeks.map { week in
            WeeklyPointsUpload(weekStart: SocialDay.string(week.start, calendar: calendar), points: week.total, planned: week.planned,
                               fullWeek: week.fullWeek, streak: week.streak, load: week.load, updatedAt: now)
        })

        if let challenges = try? await api.challenges() {
            var values: [UUID: Double] = [:]
            for challenge in challenges where challenge.joined {
                values[challenge.id] = Self.progress(challenge, activities: activities, planned: planned, calendar: calendar, now: now)
            }
            try? await api.updateProgress(values)
        }
    }

    /// Your progress in a friends' challenge (km, sessions, days or points).
    static func progress(_ challenge: FriendChallenge, activities: [ActivityRecord], planned: [PlannedRecord], calendar: Calendar, now: Date) -> Double {
        guard let start = SocialDay.date(challenge.startsOn, calendar: calendar),
              let last = SocialDay.date(challenge.endsOn, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return 0 }
        let inside = activities.filter { $0.start >= start && $0.start < end }
        switch challenge.metric {
        case .runKilometres: return (inside.filter { $0.kind == .run }.reduce(0) { $0 + $1.distanceMeters } / 100).rounded(.down) / 10
        case .gymSessions: return Double(inside.filter { $0.kind == .gym || $0.kind == .functional }.count)
        case .activeDays: return Double(Set(inside.map { calendar.startOfDay(for: $0.start) }).count)
        case .points:
            let weeks = Points.weeks(activities, planned: planned, now: now, calendar: calendar)
            return Double(weeks.filter { $0.start >= calendar.startOfISOWeek(for: start) && $0.start < end }.reduce(0) { $0 + $1.total })
        }
    }

    private static func upload(_ run: RunLogModel) -> SharedSessionUpload {
        SharedSessionUpload(id: run.id, kind: "run", title: run.title.isEmpty ? "Run" : run.title, startedAt: run.startedAt,
                            durationSeconds: run.durationSeconds, distanceMeters: run.distanceMeters, load: run.load,
                            runType: run.runTypeRaw, averageHeartRate: nil, sets: 0,
                            route: run.isTreadmill ? nil : RoutePrivacy.trimmed(run.route), updatedAt: run.updatedAt)
    }

    private static func upload(_ lift: StrengthLogModel) -> SharedSessionUpload {
        SharedSessionUpload(id: lift.id, kind: lift.isFunctional ? "functional" : "gym",
                            title: lift.title.isEmpty ? (lift.isFunctional ? "Workout" : "Gym session") : lift.title,
                            startedAt: lift.startedAt, durationSeconds: lift.durationSeconds, distanceMeters: lift.functionalRunMeters,
                            load: lift.load, runType: nil, averageHeartRate: nil,
                            sets: lift.sets.filter { $0.isCompleted && !$0.isSoftDeleted }.count, route: nil, updatedAt: lift.updatedAt)
    }
}
