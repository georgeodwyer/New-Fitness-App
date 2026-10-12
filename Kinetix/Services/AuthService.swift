import Foundation
import Observation
import CryptoKit
import KinetixSync

/// Account state: signed in or out, using Supabase. Keeps the session in the Keychain.
@Observable
@MainActor
final class AuthService {
    enum State: Equatable {
        /// Supabase isn't configured in this build (no URL/key): accounts are off.
        case unavailable
        case signedOut
        case signedIn(email: String?, userId: UUID)
    }

    static let shared = AuthService()
    private static let keychainAccount = "session"

    private(set) var state: State = .unavailable
    @ObservationIgnored private(set) var client: SupabaseClient?
    @ObservationIgnored private let useKeychain: Bool

    init(config: SupabaseConfig? = SupabaseConfig(info: Bundle.main.infoDictionary), transport: HTTPTransport = URLSessionTransport(),
         useKeychain: Bool = true) {
        self.useKeychain = useKeychain
        guard let config else { return }
        let stored = useKeychain ? Keychain.load(account: Self.keychainAccount).flatMap { try? JSONDecoder().decode(AuthSession.self, from: $0) } : nil
        let client = SupabaseClient(config: config, transport: transport, session: stored)
        self.client = client
        state = stored.map { .signedIn(email: $0.email, userId: $0.userId) } ?? .signedOut
        Task {
            await client.setSessionObserver { session in
                Task { @MainActor in AuthService.sessionChanged(session, useKeychain: useKeychain, service: self) }
            }
        }
    }

    private static func sessionChanged(_ session: AuthSession?, useKeychain: Bool, service: AuthService) {
        if useKeychain {
            if let session, let data = try? JSONEncoder().encode(session) {
                Keychain.save(data, account: keychainAccount)
            } else {
                Keychain.delete(account: keychainAccount)
            }
        }
        service.state = session.map { .signedIn(email: $0.email, userId: $0.userId) } ?? .signedOut
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var email: String? {
        if case .signedIn(let email, _) = state { return email }
        return nil
    }

    var userId: UUID? {
        if case .signedIn(_, let id) = state { return id }
        return nil
    }

    // MARK: Actions

    func signIn(email: String, password: String) async throws {
        guard let client else { throw SupabaseError.notSignedIn }
        let session = try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        Self.sessionChanged(session, useKeychain: useKeychain, service: self)
    }

    /// Returns true if signed in straight away, false if the user must confirm their email first.
    func signUp(email: String, password: String) async throws -> Bool {
        guard let client else { throw SupabaseError.notSignedIn }
        switch try await client.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password) {
        case .signedIn(let session):
            Self.sessionChanged(session, useKeychain: useKeychain, service: self)
            return true
        case .confirmationRequired:
            return false
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        guard let client else { throw SupabaseError.notSignedIn }
        let session = try await client.signInWithApple(idToken: idToken, nonce: nonce)
        Self.sessionChanged(session, useKeychain: useKeychain, service: self)
    }

    func sendPasswordReset(email: String) async throws {
        guard let client else { throw SupabaseError.notSignedIn }
        try await client.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
    }

    func signOut() async {
        await client?.signOut()
        Self.sessionChanged(nil, useKeychain: useKeychain, service: self)
    }

    /// Deletes the cloud account and its data.
    func deleteAccount() async throws {
        guard let client else { return }
        try await client.deleteAccount()
        Self.sessionChanged(nil, useKeychain: useKeychain, service: self)
    }

    // MARK: Sign in with Apple helpers

    /// A random nonce; its SHA-256 goes to Apple, the raw value to Supabase.
    static func makeNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int(generator.next() % UInt64(characters.count))] })
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
