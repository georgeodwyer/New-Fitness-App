import Foundation
import Observation
import SwiftData
import KinetixSync

/// Syncs local data with the cloud: uploads local changes, downloads newer changes
/// from other devices (last write wins per record), and keeps one active profile and plan.
@Observable
@MainActor
final class SyncService {
    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    static let shared = SyncService()

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date? = UserDefaults.standard.object(forKey: "sync.lastSyncedAt") as? Date

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var auth: AuthService = .shared
    @ObservationIgnored private var pendingTask: Task<Void, Never>?

    /// Called at launch.
    func configure(container: ModelContainer, auth: AuthService = .shared) {
        self.container = container
        self.auth = auth
    }

    /// Asks for a sync soon (debounced), e.g. after finishing a workout.
    func requestSync(after delay: Double = 2) {
        guard auth.isSignedIn else { return }
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let container = self.container else { return }
            await self.sync(context: container.mainContext)
        }
    }

    /// Full sync now. Errors are recorded in `status` (the app keeps working offline).
    func sync(context: ModelContext) async {
        guard let client = auth.client, let userId = auth.userId, status != .syncing else { return }
        status = .syncing
        do {
            try await Self.sync(context: context, client: client, userId: userId)
            lastSyncedAt = .now
            UserDefaults.standard.set(lastSyncedAt, forKey: "sync.lastSyncedAt")
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// The sync algorithm (static so tests can drive it with a fake server).
    static func sync(context: ModelContext, client: SupabaseClient, userId: UUID, defaults: UserDefaults = .standard) async throws {
        // New account on this device: upload everything stored locally to it.
        if defaults.string(forKey: "sync.lastUserId") != userId.uuidString {
            for type in SyncRegistry.types { markAllForUpload(type, in: context) }
            defaults.removeObject(forKey: cursorKey(userId))
            defaults.set(userId.uuidString, forKey: "sync.lastUserId")
        }

        // 1) Upload local changes.
        var uploaded: [(any SyncableModel, Date)] = []
        var records: [SyncRecord] = []
        for type in SyncRegistry.types {
            let changed = changedModels(type, in: context)
            for model in changed {
                records.append(try model.syncRecord())
                uploaded.append((model, model.updatedAt))
            }
        }
        if !records.isEmpty {
            try await client.push(records)
            // Only clear the flag if nothing changed while uploading.
            for (model, stamp) in uploaded where model.updatedAt == stamp { model.needsSync = false }
            try? context.save()
        }

        // 2) Download changes from other devices.
        let (pulled, cursor) = try await client.pull(after: defaults.string(forKey: cursorKey(userId)))
        let byType = Dictionary(grouping: pulled, by: \.type)
        for type in SyncRegistry.types {
            guard let incoming = byType[type.syncType] else { continue }
            try apply(incoming, as: type, in: context)
        }
        reconcileSingletons(in: context)
        try? context.save()
        if let cursor { defaults.set(cursor, forKey: cursorKey(userId)) }
    }

    static func cursorKey(_ userId: UUID) -> String { "sync.cursor.\(userId.uuidString)" }

    private static func changedModels<T: SyncableModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter(\.needsSync)
    }

    private static func markAllForUpload<T: SyncableModel>(_ type: T.Type, in context: ModelContext) {
        for model in (try? context.fetch(FetchDescriptor<T>())) ?? [] { model.needsSync = true }
    }

    private static func apply<T: SyncableModel>(_ records: [SyncRecord], as type: T.Type, in context: ModelContext) throws {
        let existing = Dictionary(((try? context.fetch(FetchDescriptor<T>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for record in records {
            let local = existing[record.id]
            // An unsynced local edit that's newer wins; it'll upload next time.
            guard SyncMerge.decide(localUpdatedAt: local?.updatedAt, remote: record) == .applyRemote else { continue }
            let model = local ?? {
                let created = T.makeForSync(id: record.id)
                context.insert(created)
                return created
            }()
            try model.apply(record, context: context)
        }
    }

    /// Two devices may each have created a profile, settings or an active plan before
    /// syncing. Keep the most recently edited one.
    static func reconcileSingletons(in context: ModelContext) {
        func newestFirst<T: SyncTracked & PersistentModel>(_ type: T.Type) -> [T] {
            ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter { !$0.isSoftDeleted }.sorted { $0.updatedAt > $1.updatedAt }
        }
        for profile in newestFirst(UserProfileModel.self).dropFirst() { profile.softDelete() }
        for settings in newestFirst(CoachingSettingsModel.self).dropFirst() { settings.softDelete() }
        for plan in newestFirst(TrainingPlanModel.self).filter(\.isActive).dropFirst() {
            plan.isActive = false
            plan.touch()
        }
    }
}
