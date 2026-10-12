import Foundation

/// Any JSON value (used for the free-form `payload` of a synced record).
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Converts any Encodable into a JSON value (via JSON).
    public static func from<T: Encodable>(_ value: T, encoder: JSONEncoder = SyncCoding.encoder) throws -> JSONValue {
        try SyncCoding.decoder.decode(JSONValue.self, from: encoder.encode(value))
    }

    /// Decodes this JSON value into a Decodable type.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try SyncCoding.decoder.decode(type, from: SyncCoding.encoder.encode(self))
    }
}

/// Shared JSON settings: ISO-8601 dates with fractional seconds (what Postgres returns).
public enum SyncCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date \(text)")
            }
            return date
        }
        return decoder
    }()

    public static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Parses ISO-8601 with or without fractional seconds, including Postgres's
    /// microsecond precision ("2026-10-12T09:30:00.123456+00:00").
    public static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // Trim fractional seconds beyond milliseconds, which ISO8601DateFormatter rejects.
        if let dot = text.firstIndex(of: ".") {
            let afterDot = text[text.index(after: dot)...]
            let digits = afterDot.prefix { $0.isNumber }
            let rest = afterDot.dropFirst(digits.count)
            let trimmed = String(text[..<dot]) + "." + String(digits.prefix(3)) + rest
            return withFraction.date(from: trimmed)
        }
        return nil
    }
}
