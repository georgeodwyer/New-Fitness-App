import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends HTTP requests (URLSession in the app; a stub in tests).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
            return (data, http)
        } catch let error as SupabaseError {
            throw error
        } catch {
            throw SupabaseError.network(error.localizedDescription)
        }
    }
}

/// Minimal Supabase client: email + Apple sign-in, token refresh, sign-out, account
/// deletion, and record upload/download through the REST API.
public actor SupabaseClient {
    public let config: SupabaseConfig
    private let transport: HTTPTransport
    public private(set) var session: AuthSession?
    /// Called whenever the session changes (store it in the Keychain).
    private var onSessionChange: (@Sendable (AuthSession?) -> Void)?

    public init(config: SupabaseConfig, transport: HTTPTransport = URLSessionTransport(), session: AuthSession? = nil) {
        self.config = config
        self.transport = transport
        self.session = session
    }

    public func setSessionObserver(_ observer: @escaping @Sendable (AuthSession?) -> Void) {
        onSessionChange = observer
    }

    private func setSession(_ newValue: AuthSession?) {
        session = newValue
        onSessionChange?(newValue)
    }

    // MARK: - Auth

    public func signUp(email: String, password: String) async throws -> SignUpResult {
        let data = try await post("auth/v1/signup", body: ["email": email, "password": password], authorized: false)
        let response = try SyncCoding.decoder.decode(TokenResponse.self, from: data)
        if let session = response.session(now: Date()) {
            setSession(session)
            return .signedIn(session)
        }
        return .confirmationRequired(email: email)
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        try await token(grant: "password", body: ["email": email, "password": password])
    }

    /// Native Sign in with Apple: the identity token from AuthenticationServices plus the
    /// raw nonce whose SHA-256 was sent to Apple.
    public func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        try await token(grant: "id_token", body: ["provider": "apple", "id_token": idToken, "nonce": nonce])
    }

    public func sendPasswordReset(email: String) async throws {
        _ = try await post("auth/v1/recover", body: ["email": email], authorized: false)
    }

    public func refresh() async throws -> AuthSession {
        guard let current = session else { throw SupabaseError.notSignedIn }
        do {
            return try await token(grant: "refresh_token", body: ["refresh_token": current.refreshToken])
        } catch let error as SupabaseError where error.isAuthFailure || { if case .server(400, _) = error { return true }; return false }() {
            // The refresh token is no longer valid: the user must sign in again.
            setSession(nil)
            throw error
        }
    }

    public func signOut() async {
        if session != nil {
            _ = try? await post("auth/v1/logout", body: [String: String](), authorized: true)
        }
        setSession(nil)
    }

    /// Deletes the user's account and all their cloud records (server-side function).
    public func deleteAccount() async throws {
        _ = try await post("rest/v1/rpc/delete_my_account", body: [String: String](), authorized: true)
        setSession(nil)
    }

    private func token(grant: String, body: [String: String]) async throws -> AuthSession {
        let data = try await post("auth/v1/token?grant_type=\(grant)", body: body, authorized: false)
        guard let session = try SyncCoding.decoder.decode(TokenResponse.self, from: data).session(now: Date()) else {
            throw SupabaseError.invalidResponse
        }
        setSession(session)
        return session
    }

    // MARK: - Records

    /// Uploads records (insert or update by id). The server keeps whichever copy has the
    /// newer `updated_at`, so an older upload never overwrites a newer edit.
    public func push(_ records: [SyncRecord], batchSize: Int = 200) async throws {
        var start = 0
        while start < records.count {
            let batch = Array(records[start..<min(start + batchSize, records.count)]).map(\.upload)
            _ = try await send(path: "rest/v1/records?on_conflict=id", method: "POST", body: SyncCoding.encoder.encode(batch),
                               headers: ["Prefer": "resolution=merge-duplicates,return=minimal"], authorized: true)
            start += batchSize
        }
    }

    /// Downloads records changed on the server after `cursor` (the last `server_updated_at`
    /// seen), oldest first. Returns the records and the new cursor.
    public func pull(after cursor: String?, pageSize: Int = 500) async throws -> (records: [SyncRecord], cursor: String?) {
        var all: [SyncRecord] = []
        var current = cursor
        while true {
            var path = "rest/v1/records?select=id,type,updated_at,deleted_at,payload,server_updated_at&order=server_updated_at.asc&limit=\(pageSize)"
            if let current { path += "&server_updated_at=gt.\(Self.encodeQueryValue(current))" }
            let data = try await send(path: path, method: "GET", body: nil, headers: [:], authorized: true)
            let page = try SyncCoding.decoder.decode([SyncRecord].self, from: data)
            all += page
            if let last = page.last?.serverUpdatedAt { current = last }
            if page.count < pageSize { break }
        }
        return (all, current)
    }

    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - HTTP

    private func post<Body: Encodable>(_ path: String, body: Body, authorized: Bool) async throws -> Data {
        try await send(path: path, method: "POST", body: SyncCoding.encoder.encode(body), headers: [:], authorized: authorized)
    }

    private func send(path: String, method: String, body: Data?, headers: [String: String], authorized: Bool, retried: Bool = false) async throws -> Data {
        if authorized, let current = session, current.needsRefresh(), !retried {
            _ = try await refresh()
        }
        guard let url = URL(string: path, relativeTo: config.url.appendingPathComponent("")) else { throw SupabaseError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if authorized {
            guard let token = session?.accessToken else { throw SupabaseError.notSignedIn }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await transport.send(request)
        if (200..<300).contains(response.statusCode) { return data }
        // Expired token: refresh once and retry.
        if response.statusCode == 401, authorized, !retried, session != nil {
            _ = try await refresh()
            return try await send(path: path, method: method, body: body, headers: headers, authorized: authorized, retried: true)
        }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.text ?? "Request failed (\(response.statusCode))"
        throw SupabaseError.server(status: response.statusCode, message: message)
    }
}
