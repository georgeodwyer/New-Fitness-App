import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where Kinetix talks to Strava.
///
/// The client ID is public, but the client secret shouldn't ship in the app, so normally the
/// code-for-token exchange (and token refresh) goes through a small Supabase Edge Function
/// (`supabase/functions/strava-token`) that holds the secret. Until Supabase is set up, a
/// build can instead carry the secret and talk to Strava directly (fine for testing; switch
/// to the Edge Function before release; see docs/STRAVA.md).
public struct StravaConfig: Equatable, Sendable {
    public var clientID: String
    public var tokenExchangeURL: URL
    /// Sent as `apikey` to the Edge Function.
    public var supabaseAnonKey: String
    /// Only in builds without Supabase: the exchange then goes straight to Strava.
    public var clientSecret: String?
    public var redirectURI: String

    public static let directTokenURL = URL(string: "https://www.strava.com/oauth/token")!

    public static let callbackScheme = "kinetix"
    /// Strava's app settings must use "localhost" as the Authorization Callback Domain.
    public static let defaultRedirectURI = "kinetix://localhost/strava"

    public init(clientID: String, tokenExchangeURL: URL, supabaseAnonKey: String, clientSecret: String? = nil,
                redirectURI: String = StravaConfig.defaultRedirectURI) {
        self.clientID = clientID
        self.tokenExchangeURL = tokenExchangeURL
        self.supabaseAnonKey = supabaseAnonKey
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
    }

    /// Talks to Strava directly, carrying the client secret (testing builds without Supabase).
    public static func direct(clientID: String, clientSecret: String) -> StravaConfig {
        StravaConfig(clientID: clientID, tokenExchangeURL: directTokenURL, supabaseAnonKey: "", clientSecret: clientSecret)
    }

    public var isDirect: Bool { clientSecret != nil }

    /// Reads `StravaClientID` plus either the Supabase settings (preferred) or
    /// `StravaClientSecret` from Info.plist. nil when Strava can't work in this build.
    public init?(info: [String: Any]?) {
        guard let clientID = (info?["StravaClientID"] as? String)?.trimmingCharacters(in: .whitespaces),
              !clientID.isEmpty, clientID.allSatisfy(\.isNumber) else { return nil }
        if let supabase = SupabaseConfig(info: info) {
            self.init(clientID: clientID,
                      tokenExchangeURL: supabase.url.appendingPathComponent("functions/v1/strava-token"),
                      supabaseAnonKey: supabase.anonKey)
        } else if let secret = (info?["StravaClientSecret"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !secret.isEmpty, !secret.hasPrefix("$(") {
            self = .direct(clientID: clientID, clientSecret: secret)
        } else {
            return nil
        }
    }
}

public struct StravaTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var athleteId: Int?
    public var athleteName: String?
    /// Permissions the athlete granted (nil for connections made before Kinetix asked to read).
    public var scopes: [String]?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, athleteId: Int? = nil, athleteName: String? = nil,
                scopes: [String]? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.athleteId = athleteId
        self.athleteName = athleteName
        self.scopes = scopes
    }

    /// Allowed to read activities (for importing them).
    public var canReadActivities: Bool { scopes?.contains { $0.hasPrefix("activity:read") } ?? false }

    public func needsRefresh(now: Date = Date()) -> Bool { now.addingTimeInterval(120) >= expiresAt }
}

public enum StravaError: Error, Equatable, LocalizedError, Sendable {
    case notConnected
    case cancelled
    case denied
    /// The athlete unticked "Upload your activities" on Strava's permission screen.
    case missingUploadPermission
    case invalidCallback
    case server(status: Int, message: String)
    case uploadFailed(String)
    case processingTimedOut
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Strava isn't connected."
        case .cancelled: return "Connecting to Strava was cancelled."
        case .denied: return "Strava access wasn't allowed."
        case .missingUploadPermission: return "Kinetix needs permission to upload activities. Connect again and leave “Upload your activities” ticked."
        case .invalidCallback: return "Strava sent back an unexpected response. Please try again."
        case .server(_, let message): return "Strava: \(message)"
        case .uploadFailed(let message): return "Strava couldn't process the upload: \(message)"
        case .processingTimedOut: return "Strava is still processing the upload. It'll be checked again later."
        case .network(let message): return "Couldn't reach Strava (\(message)). The upload will be retried."
        }
    }

    /// Worth retrying later (offline, rate limited, Strava busy).
    public var isTransient: Bool {
        switch self {
        case .network, .processingTimedOut: return true
        case .server(let status, _): return status == 429 || status >= 500
        default: return false
        }
    }
}

/// Result of checking an upload.
public struct StravaUploadStatus: Decodable, Equatable, Sendable {
    public var id: Int
    public var activityId: Int?
    public var error: String?
    public var status: String?

    enum CodingKeys: String, CodingKey {
        case id, error, status
        case activityId = "activity_id"
    }

    public init(id: Int, activityId: Int? = nil, error: String? = nil, status: String? = nil) {
        self.id = id
        self.activityId = activityId
        self.error = error
        self.status = status
    }

    /// Strava rejects a file it has seen before with "… duplicate of activity 123…"; that
    /// activity is the one to link to.
    public var duplicateActivityId: Int? {
        guard let error, let range = error.range(of: "duplicate of ", options: .caseInsensitive) else { return nil }
        let rest = error[range.upperBound...]
        let digits = rest.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }
}

/// Strava OAuth, GPX upload and manual activities over plain HTTPS.
public actor StravaClient {
    public let config: StravaConfig
    private let transport: HTTPTransport
    private let apiBase = URL(string: "https://www.strava.com")!
    public private(set) var tokens: StravaTokens?
    private var onTokensChange: (@Sendable (StravaTokens?) -> Void)?
    private let sleep: @Sendable (Double) async -> Void

    public init(config: StravaConfig, transport: HTTPTransport = URLSessionTransport(), tokens: StravaTokens? = nil,
                sleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.config = config
        self.transport = transport
        self.tokens = tokens
        self.sleep = sleep
    }

    public func setTokenObserver(_ observer: @escaping @Sendable (StravaTokens?) -> Void) {
        onTokensChange = observer
    }

    private func setTokens(_ newValue: StravaTokens?) {
        tokens = newValue
        onTokensChange?(newValue)
    }

    // MARK: - OAuth

    /// The page that asks the athlete to allow Kinetix to upload activities.
    public nonisolated func authorizeURL(state: String) -> URL {
        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "read,activity:write"),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    /// Pulls the authorisation code out of the redirect, checking state and permission.
    public static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if value("error") != nil { throw StravaError.denied }
        guard value("state") == expectedState, let code = value("code"), !code.isEmpty else { throw StravaError.invalidCallback }
        let scopes = (value("scope") ?? "").split(separator: ",").map(String.init)
        guard scopes.contains("activity:write") else { throw StravaError.missingUploadPermission }
        return code
    }

    /// The permissions granted, from the redirect ("read,activity:write").
    public static func grantedScopes(from callback: URL) -> [String] {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return (items.first { $0.name == "scope" }?.value ?? "").split(separator: ",").map(String.init)
    }

    /// Swaps the authorisation code for tokens (via the Edge Function, or Strava directly).
    @discardableResult
    public func connect(code: String, scopes: [String]? = nil) async throws -> StravaTokens {
        let response = try await exchange(["grant_type": "authorization_code", "code": code])
        var tokens = response.tokens(keeping: nil)
        tokens.scopes = scopes
        setTokens(tokens)
        return tokens
    }

    /// Revokes access on Strava (best effort) and forgets the tokens.
    public func disconnect() async {
        if let token = tokens?.accessToken {
            var request = URLRequest(url: apiBase.appendingPathComponent("oauth/deauthorize"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await transport.send(request)
        }
        setTokens(nil)
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw StravaError.notConnected }
        if !forceRefresh && !current.needsRefresh() { return current.accessToken }
        do {
            let response = try await exchange(["grant_type": "refresh_token", "refresh_token": current.refreshToken])
            let refreshed = response.tokens(keeping: current)
            setTokens(refreshed)
            return refreshed.accessToken
        } catch StravaError.server(let status, _) where status == 400 || status == 401 {
            // Access was revoked on strava.com.
            setTokens(nil)
            throw StravaError.notConnected
        }
    }

    private func exchange(_ body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: config.tokenExchangeURL)
        request.httpMethod = "POST"
        if let secret = config.clientSecret {
            let fields = [("client_id", config.clientID), ("client_secret", secret)] + body.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            request.httpBody = Data(Self.formURLEncoded(fields).utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw StravaError.invalidCallback
        }
    }

    // MARK: - Activities

    /// Uploads a GPX file and waits for Strava to turn it into an activity. Returns the
    /// activity id. `externalId` makes repeat uploads of the same run detectable.
    public func uploadGPX(_ gpx: String, name: String, description: String?, externalId: String) async throws -> Int {
        var form = MultipartForm()
        form.addField("data_type", "gpx")
        form.addField("name", name)
        if let description { form.addField("description", description) }
        form.addField("external_id", externalId)
        form.addFile("file", filename: "\(externalId).gpx", contentType: "application/gpx+xml", data: Data(gpx.utf8))

        let data = try await authorized(path: "api/v3/uploads", method: "POST", body: form.finished, contentType: form.contentType)
        let status = try decodeStatus(data)
        return try await waitForActivity(status)
    }

    func waitForActivity(_ initial: StravaUploadStatus, attempts: Int = 10, delay: Double = 2) async throws -> Int {
        var status = initial
        for attempt in 0...attempts {
            if let id = status.activityId { return id }
            if let duplicate = status.duplicateActivityId { return duplicate }
            if let error = status.error, !error.isEmpty { throw StravaError.uploadFailed(error) }
            guard attempt < attempts else { break }
            await sleep(delay)
            status = try decodeStatus(try await authorized(path: "api/v3/uploads/\(status.id)", method: "GET", body: nil, contentType: nil))
        }
        throw StravaError.processingTimedOut
    }

    /// Checks an upload that timed out earlier.
    public func activityId(forUpload uploadId: Int) async throws -> Int? {
        let status = try decodeStatus(try await authorized(path: "api/v3/uploads/\(uploadId)", method: "GET", body: nil, contentType: nil))
        if let error = status.error, status.duplicateActivityId == nil, !error.isEmpty { throw StravaError.uploadFailed(error) }
        return status.activityId ?? status.duplicateActivityId
    }

    /// The athlete's activities that started after `after`, one page at a time (Strava's
    /// maximum page size is 200).
    public func activities(after: Date, page: Int = 1, perPage: Int = 100) async throws -> [StravaActivity] {
        let query = [URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))),
                     URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "per_page", value: String(perPage))]
        let data = try await authorized(path: "api/v3/athlete/activities", method: "GET", body: nil, contentType: nil, query: query)
        do {
            return try StravaActivity.decoder.decode([StravaActivity].self, from: data)
        } catch {
            throw StravaError.invalidCallback
        }
    }

    /// Creates an activity without a GPS file (used for strength sessions).
    public func createActivity(name: String, sportType: String, start: Date, elapsedSeconds: Int, description: String?,
                               timeZone: TimeZone = .current) async throws -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        var fields = [
            ("name", name),
            ("sport_type", sportType),
            ("start_date_local", formatter.string(from: start)),
            ("elapsed_time", String(max(1, elapsedSeconds)))
        ]
        if let description { fields.append(("description", description)) }
        let body = Self.formURLEncoded(fields)
        let data = try await authorized(path: "api/v3/activities", method: "POST", body: Data(body.utf8),
                                        contentType: "application/x-www-form-urlencoded")
        struct Created: Decodable { var id: Int }
        guard let created = try? JSONDecoder().decode(Created.self, from: data) else { throw StravaError.invalidCallback }
        return created.id
    }

    static func formURLEncoded(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
    }

    // MARK: - HTTP

    private func decodeStatus(_ data: Data) throws -> StravaUploadStatus {
        guard let status = try? JSONDecoder().decode(StravaUploadStatus.self, from: data) else { throw StravaError.invalidCallback }
        return status
    }

    private func authorized(path: String, method: String, body: Data?, contentType: String?, query: [URLQueryItem] = [],
                            retried: Bool = false) async throws -> Data {
        let token = try await validAccessToken(forceRefresh: retried)
        var components = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            return try await perform(request)
        } catch StravaError.server(let status, _) where status == 401 && !retried {
            return try await authorized(path: path, method: method, body: body, contentType: contentType, query: query, retried: true)
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as SupabaseError {
            if case .network(let message) = error { throw StravaError.network(message) }
            throw StravaError.network(error.localizedDescription)
        } catch {
            throw StravaError.network(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(StravaErrorBody.self, from: data))?.text ?? "Request failed (\(response.statusCode))"
            throw StravaError.server(status: response.statusCode, message: message)
        }
        return data
    }

    struct TokenResponse: Decodable {
        struct Athlete: Decodable {
            var id: Int?
            var firstname: String?
            var lastname: String?
        }
        var accessToken: String
        var refreshToken: String
        var expiresAt: Double
        var athlete: Athlete?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case athlete
        }

        func tokens(keeping previous: StravaTokens?) -> StravaTokens {
            let name = [athlete?.firstname, athlete?.lastname].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return StravaTokens(accessToken: accessToken, refreshToken: refreshToken,
                                expiresAt: Date(timeIntervalSince1970: expiresAt),
                                athleteId: athlete?.id ?? previous?.athleteId,
                                athleteName: name.isEmpty ? previous?.athleteName : name,
                                scopes: previous?.scopes)
        }
    }

    struct StravaErrorBody: Decodable {
        struct Detail: Decodable { var field: String?; var code: String? }
        var message: String?
        var error: String?
        var errors: [Detail]?

        var text: String? {
            if let detail = errors?.first, let field = detail.field, let code = detail.code { return "\(message ?? "Error"): \(field) \(code)" }
            return error ?? message
        }
    }
}

/// Builds a multipart/form-data body.
struct MultipartForm {
    let boundary = "kinetix-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    /// Call once after the last part (done by `body` users through `finished`).
    var finished: Data { body + Data("--\(boundary)--\r\n".utf8) }
}

// MARK: - Activities from Strava

/// One activity from the athlete's Strava feed (summary fields only).
public struct StravaActivity: Decodable, Equatable, Sendable {
    public struct Map: Decodable, Equatable, Sendable {
        public var summaryPolyline: String?
        enum CodingKeys: String, CodingKey { case summaryPolyline = "summary_polyline" }
        public init(summaryPolyline: String?) { self.summaryPolyline = summaryPolyline }
    }

    public var id: Int
    public var name: String
    /// e.g. "Run", "TrailRun", "Ride", "WeightTraining".
    public var sportType: String
    public var startDate: Date
    /// Seconds, including pauses.
    public var elapsedTime: Int
    /// Seconds moving.
    public var movingTime: Int
    /// Metres.
    public var distance: Double
    public var averageHeartrate: Double?
    public var maxHeartrate: Double?
    /// Set by the app that uploaded it; Kinetix's own uploads start "kinetix-".
    public var externalId: String?
    public var map: Map?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, map, type
        case sportType = "sport_type"
        case startDate = "start_date"
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case externalId = "external_id"
    }

    public init(id: Int, name: String, sportType: String, startDate: Date, elapsedTime: Int, movingTime: Int, distance: Double,
                averageHeartrate: Double? = nil, maxHeartrate: Double? = nil, externalId: String? = nil, map: Map? = nil) {
        self.id = id
        self.name = name
        self.sportType = sportType
        self.startDate = startDate
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
        self.distance = distance
        self.averageHeartrate = averageHeartrate
        self.maxHeartrate = maxHeartrate
        self.externalId = externalId
        self.map = map
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Activity"
        // Older activities may only have the legacy "type".
        sportType = try container.decodeIfPresent(String.self, forKey: .sportType)
            ?? container.decodeIfPresent(String.self, forKey: .type) ?? "Workout"
        startDate = try container.decode(Date.self, forKey: .startDate)
        elapsedTime = try container.decodeIfPresent(Int.self, forKey: .elapsedTime) ?? 0
        movingTime = try container.decodeIfPresent(Int.self, forKey: .movingTime) ?? elapsedTime
        distance = try container.decodeIfPresent(Double.self, forKey: .distance) ?? 0
        averageHeartrate = try container.decodeIfPresent(Double.self, forKey: .averageHeartrate)
        maxHeartrate = try container.decodeIfPresent(Double.self, forKey: .maxHeartrate)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        map = try container.decodeIfPresent(Map.self, forKey: .map)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// What it is, for Kinetix's purposes.
    public enum Category: Equatable, Sendable { case run, strength, cycling, walking, other }

    public var category: Category {
        switch sportType {
        case "Run", "TrailRun", "VirtualRun": return .run
        case "WeightTraining", "Crossfit", "HighIntensityIntervalTraining", "Workout": return .strength
        case "Ride", "VirtualRide", "MountainBikeRide", "GravelRide", "EBikeRide", "EMountainBikeRide", "Velomobile", "Handcycle": return .cycling
        case "Walk", "Hike": return .walking
        default: return .other
        }
    }

    /// Uploaded by Kinetix itself (so not imported back).
    public var isFromKinetix: Bool { externalId?.hasPrefix("kinetix-") ?? false }

    /// The route's points from Strava's summary map. Empty without GPS.
    public var routeCoordinates: [Polyline.Point] {
        map?.summaryPolyline.map(Polyline.decode) ?? []
    }

    public var endDate: Date { startDate.addingTimeInterval(TimeInterval(max(elapsedTime, movingTime))) }
}

/// Google's encoded polyline format (used by Strava for maps).
public enum Polyline {
    public struct Point: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
    }

    public static func decode(_ encoded: String) -> [Point] {
        var result: [Point] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var latitude = 0, longitude = 0
        func nextValue() -> Int? {
            var shift = 0, value = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                index += 1
                value |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { return (value & 1) != 0 ? ~(value >> 1) : (value >> 1) }
            }
            return nil
        }
        while index < bytes.count {
            guard let dLat = nextValue(), let dLon = nextValue() else { break }
            latitude += dLat
            longitude += dLon
            result.append(Point(latitude: Double(latitude) / 1e5, longitude: Double(longitude) / 1e5))
        }
        return result
    }
}
