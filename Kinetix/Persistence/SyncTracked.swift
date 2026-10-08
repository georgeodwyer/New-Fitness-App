import Foundation

/// Every stored record carries these fields so it can be synced to Supabase
/// later with last-write-wins conflict handling:
/// - `id`: stable UUID shared between devices and the server
/// - `updatedAt`: the newer write wins when two devices disagree
/// - `deletedAt`: soft delete, so deletions sync too (rows are purged after sync)
/// - `needsSync`: set on every local change, cleared once uploaded
protocol SyncTracked: AnyObject {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var needsSync: Bool { get set }
}

extension SyncTracked {
    /// Call after any user edit.
    func touch(now: Date = .now) {
        updatedAt = now
        needsSync = true
    }

    func softDelete(now: Date = .now) {
        deletedAt = now
        touch(now: now)
    }

    var isSoftDeleted: Bool { deletedAt != nil }
}

/// Small helpers for storing engine value types as JSON blobs.
/// (Structured engine types go in `Data` columns: simpler and more robust than
/// asking SwiftData to model nested enums.)
enum StoredJSON {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
