import Foundation

/// One row of the `records` table: any synced item, identified by id and type,
/// with its data as JSON.
public struct SyncRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var type: String
    /// When the item was last edited (on whichever device). Newest wins.
    public var updatedAt: Date
    /// Soft delete: deletions sync like edits.
    public var deletedAt: Date?
    public var payload: JSONValue
    /// Set by the server on every accepted write; used as the download cursor.
    public var serverUpdatedAt: String?

    public init(id: UUID, type: String, updatedAt: Date, deletedAt: Date?, payload: JSONValue, serverUpdatedAt: String? = nil) {
        self.id = id
        self.type = type
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.payload = payload
        self.serverUpdatedAt = serverUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, type, payload
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    /// Upload form (the server fills in user and server timestamp).
    struct Upload: Encodable {
        var id: UUID
        var type: String
        var updatedAt: Date
        var deletedAt: Date?
        var payload: JSONValue

        enum CodingKeys: String, CodingKey {
            case id, type, payload
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(type, forKey: .type)
            try container.encode(updatedAt, forKey: .updatedAt)
            // Always send deleted_at (null when not deleted) so un-deleting syncs too.
            if let deletedAt { try container.encode(deletedAt, forKey: .deletedAt) } else { try container.encodeNil(forKey: .deletedAt) }
            try container.encode(payload, forKey: .payload)
        }
    }

    var upload: Upload { Upload(id: id, type: type, updatedAt: updatedAt, deletedAt: deletedAt, payload: payload) }
}

/// Last-write-wins decisions.
public enum SyncMerge {
    public enum Decision: Equatable, Sendable {
        /// The downloaded copy is newer (or there's no local copy): apply it.
        case applyRemote
        /// The local copy is newer or the same: keep it.
        case keepLocal
    }

    /// Decides what to do with a downloaded record given the local copy's last edit time.
    public static func decide(localUpdatedAt: Date?, remote: SyncRecord) -> Decision {
        guard let local = localUpdatedAt else { return .applyRemote }
        return remote.updatedAt > local ? .applyRemote : .keepLocal
    }
}
