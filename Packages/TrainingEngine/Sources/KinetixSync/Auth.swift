import Foundation

public struct SupabaseConfig: Equatable, Sendable {
    public var url: URL
    public var anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    /// Reads `SupabaseURL` and `SupabaseAnonKey` from an Info.plist dictionary.
    /// Returns nil when they're missing or still placeholders (accounts then stay off).
    public init?(info: [String: Any]?) {
        guard let urlText = (info?["SupabaseURL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (info?["SupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty, urlText.hasPrefix("https://"), !urlText.contains("your-project"),
              let url = URL(string: urlText)
        else { return nil }
        self.init(url: url, anonKey: key)
    }
}

/// A signed-in session.
public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userId: UUID
    public var email: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userId: UUID, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
        self.email = email
    }

    /// Refresh a minute before expiry.
    public func needsRefresh(now: Date = Date()) -> Bool { now.addingTimeInterval(60) >= expiresAt }
}

/// Result of creating an account.
public enum SignUpResult: Equatable, Sendable {
    case signedIn(AuthSession)
    /// The project requires email confirmation; the user must tap the link, then sign in.
    case confirmationRequired(email: String)
}

public enum SupabaseError: Error, Equatable, LocalizedError, Sendable {
    case notSignedIn
    case invalidResponse
    /// A message from the server (e.g. "Invalid login credentials").
    case server(status: Int, message: String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You're not signed in."
        case .invalidResponse: return "The server sent an unexpected response."
        case .server(_, let message): return message
        case .network(let message): return "Couldn't reach the server (\(message)). Your data is safe on this iPhone and will sync later."
        }
    }

    public var isBadRequest: Bool {
        if case .server(let status, _) = self { return status == 400 }
        return false
    }

    public var isAuthFailure: Bool {
        if case .server(let status, _) = self { return status == 401 || status == 403 }
        return false
    }
}

/// Raw GoTrue (Supabase Auth) token response.
struct TokenResponse: Decodable {
    struct User: Decodable {
        var id: UUID
        var email: String?
    }
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Double?
    var expiresAt: Double?
    var user: User?
    // Sign-up without a session returns the user object at the top level.
    var id: UUID?
    var email: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user, id, email
    }

    func session(now: Date) -> AuthSession? {
        guard let accessToken, let refreshToken, let user else { return nil }
        let expiry = expiresAt.map { Date(timeIntervalSince1970: $0) } ?? now.addingTimeInterval(expiresIn ?? 3600)
        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiry, userId: user.id, email: user.email)
    }
}

/// Supabase error bodies come in a few shapes.
struct ErrorBody: Decodable {
    var message: String?
    var msg: String?
    var errorDescription: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case message, msg, error
        case errorDescription = "error_description"
    }

    var text: String? { errorDescription ?? msg ?? message ?? error }
}
