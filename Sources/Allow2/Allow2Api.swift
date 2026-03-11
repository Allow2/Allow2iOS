import Foundation

/// Protocol for the core Allow2 check API, enabling dependency injection and testing.
///
/// The concrete implementation (`Allow2URLSessionApi`) calls `POST /serviceapi/check`
/// on the Allow2 API server.
public protocol Allow2Api: Sendable {
    /// Perform a permission check for the given child and activities.
    func check(_ request: CheckRequest) async throws -> CheckResult
}

/// Parameters for a permission check request.
public struct CheckRequest: Sendable {
    public let userId: UInt64
    public let pairId: UInt64
    public let pairToken: String
    public let deviceToken: String
    public let childId: UInt64
    public let tz: String
    public let activities: [ActivityCheck]
    public let log: Bool

    public init(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        deviceToken: String,
        childId: UInt64,
        tz: String,
        activities: [ActivityCheck],
        log: Bool = true
    ) {
        self.userId = userId
        self.pairId = pairId
        self.pairToken = pairToken
        self.deviceToken = deviceToken
        self.childId = childId
        self.tz = tz
        self.activities = activities
        self.log = log
    }
}

// MARK: - Environment

/// API environment. Controls which server endpoints are used.
public enum Allow2Environment: String, Sendable {
    case production
    case staging
    case sandbox

    public var apiBaseUrl: String {
        switch self {
        case .production: return "https://api.allow2.com"
        case .staging:    return "https://staging-api.allow2.com"
        case .sandbox:    return "https://staging-api.allow2.com"
        }
    }

    public var serviceBaseUrl: String {
        switch self {
        case .production: return "https://service.allow2.com"
        case .staging:    return "https://staging-service.allow2.com"
        case .sandbox:    return "https://staging-service.allow2.com"
        }
    }
}

// MARK: - Concrete URLSession Implementation

/// URLSession-based implementation of all Allow2 API protocols.
///
/// Conforms to `Allow2Api`, `Allow2PairingApi`, `Allow2RequestApi`,
/// `Allow2UpdatesApi`, and `Allow2FeedbackApi` so it can be used as the
/// single API client for all SDK components.
///
/// All POST requests include `format: "json"` in the body.
/// HTTP 401 responses throw `Allow2Error.notAuthorised` (device released).
public final class Allow2URLSessionApi: @unchecked Sendable,
    Allow2Api,
    Allow2PairingApi,
    Allow2RequestApi,
    Allow2UpdatesApi,
    Allow2FeedbackApi
{

    // MARK: - Properties

    public let environment: Allow2Environment
    public let deviceToken: String
    private let session: URLSession
    private let timeout: TimeInterval
    private let decoder: JSONDecoder

    // MARK: - Init

    /// Create an API client.
    ///
    /// - Parameters:
    ///   - deviceToken: Application-level token identifying this product (not the device instance).
    ///   - environment: Server environment to target.
    ///   - timeout: Request timeout in seconds (default 15).
    ///   - urlSession: Custom URLSession for testing. Uses `.shared` by default.
    public init(
        deviceToken: String,
        environment: Allow2Environment = .production,
        timeout: TimeInterval = 15,
        urlSession: URLSession? = nil
    ) {
        self.deviceToken = deviceToken
        self.environment = environment
        self.timeout = timeout
        self.session = urlSession ?? .shared

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970
    }

    // MARK: - Allow2Api (Check)

    public func check(_ request: CheckRequest) async throws -> CheckResult {
        let activityDicts: [[String: Any]] = request.activities.map { a in
            ["id": a.id, "log": a.log]
        }

        let body: [String: Any] = [
            "userId": request.userId,
            "pairId": request.pairId,
            "pairToken": request.pairToken,
            "deviceToken": request.deviceToken,
            "childId": request.childId,
            "tz": request.tz,
            "log": request.log,
            "activities": activityDicts,
            "format": "json",
        ]

        return try await post(environment.apiBaseUrl + "/serviceapi/check", body: body)
    }

    // MARK: - Allow2PairingApi

    public func initPairing(
        deviceToken: String,
        deviceName: String,
        method: PairingMethod
    ) async throws -> PairingSession {
        let path: String
        switch method {
        case .qrCode:  path = "/api/pair/qr/init"
        case .pinCode: path = "/api/pair/pin/init"
        }

        let body: [String: Any] = [
            "uuid": UUID().uuidString,
            "name": deviceName,
            "deviceToken": deviceToken,
            "platform": "apple",
            "format": "json",
        ]

        return try await post(environment.apiBaseUrl + path, body: body)
    }

    public func checkPairingStatus(sessionId: String) async throws -> PairingStatusResult {
        return try await get(environment.apiBaseUrl + "/api/pair/status/" + sessionId)
    }

    public func cancelPairing(sessionId: String) async throws {
        let body: [String: Any] = [
            "sessionId": sessionId,
            "format": "json",
        ]
        let _: EmptyResponse = try await post(environment.apiBaseUrl + "/api/pair/cancel", body: body)
    }

    // MARK: - Allow2RequestApi

    public func createRequest(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        childId: UInt64,
        activityId: UInt64?,
        minutes: Int,
        message: String?
    ) async throws -> RequestResult {
        var body: [String: Any] = [
            "userId": userId,
            "pairId": pairId,
            "pairToken": pairToken,
            "childId": childId,
            "duration": minutes,
            "format": "json",
        ]
        if let activityId = activityId {
            body["activity"] = activityId
        }
        if let message = message {
            body["message"] = message
        }

        return try await post(environment.apiBaseUrl + "/api/request/createRequest", body: body)
    }

    public func getRequestStatus(
        requestId: UInt64,
        statusSecret: String
    ) async throws -> RequestStatusResult {
        var request = URLRequest(url: URL(string: environment.apiBaseUrl + "/api/request/\(requestId)/status")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(statusSecret, forHTTPHeaderField: "X-Status-Secret")
        request.timeoutInterval = timeout

        return try await execute(request)
    }

    // MARK: - Allow2UpdatesApi

    public func getUpdates(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        deviceToken: String,
        timestampMillis: Int64?
    ) async throws -> Allow2UpdateResult {
        var components = URLComponents(string: environment.apiBaseUrl + "/api/getUpdates")!
        var queryItems = [
            URLQueryItem(name: "userId", value: String(userId)),
            URLQueryItem(name: "pairId", value: String(pairId)),
            URLQueryItem(name: "pairToken", value: pairToken),
            URLQueryItem(name: "deviceToken", value: deviceToken),
        ]
        if let ts = timestampMillis {
            queryItems.append(URLQueryItem(name: "timestampMillis", value: String(ts)))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw Allow2Error.invalidResponse
        }

        return try await get(url.absoluteString)
    }

    // MARK: - Allow2FeedbackApi

    public func submitFeedback(
        userId: UInt64,
        pairToken: String,
        pairId: UInt64?,
        vid: UInt64,
        childId: UInt64?,
        category: FeedbackCategory,
        message: String,
        deviceContext: DeviceContext?
    ) async throws -> UInt64 {
        var body: [String: Any] = [
            "userId": userId,
            "pairToken": pairToken,
            "vid": vid,
            "category": category.rawValue,
            "message": message,
            "format": "json",
        ]
        if let pairId = pairId { body["pairId"] = pairId }
        if let childId = childId { body["childId"] = childId }
        if let ctx = deviceContext {
            var ctxDict: [String: Any] = [:]
            if let v = ctx.deviceName { ctxDict["deviceName"] = v }
            if let v = ctx.platform { ctxDict["platform"] = v }
            if let v = ctx.sdkVersion { ctxDict["sdkVersion"] = v }
            if let v = ctx.productName { ctxDict["productName"] = v }
            body["deviceContext"] = ctxDict
        }

        let response: FeedbackSubmitResponse = try await post(
            environment.apiBaseUrl + "/api/feedback/submit",
            body: body
        )
        return response.discussionId
    }

    public func loadFeedback(
        userId: UInt64,
        pairToken: String,
        pairId: UInt64?
    ) async throws -> [FeedbackThread] {
        var body: [String: Any] = [
            "userId": userId,
            "pairToken": pairToken,
            "format": "json",
        ]
        if let pairId = pairId { body["pairId"] = pairId }

        let response: FeedbackLoadResponse = try await post(
            environment.apiBaseUrl + "/api/feedback/load",
            body: body
        )
        return response.discussions
    }

    public func replyToFeedback(
        userId: UInt64,
        pairToken: String,
        discussionId: UInt64,
        message: String
    ) async throws -> UInt64 {
        let body: [String: Any] = [
            "userId": userId,
            "pairToken": pairToken,
            "discussionId": discussionId,
            "message": message,
            "format": "json",
        ]

        let response: FeedbackReplyResponse = try await post(
            environment.apiBaseUrl + "/api/feedback/reply",
            body: body
        )
        return response.messageId
    }

    // MARK: - Private: HTTP

    private func post<T: Decodable>(_ urlString: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw Allow2Error.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await execute(request)
    }

    private func get<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw Allow2Error.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw Allow2Error.timeout
        } catch {
            throw Allow2Error.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Allow2Error.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw Allow2Error.notAuthorised
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message: String
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = errorBody["message"] as? String {
                message = msg
            } else {
                message = "HTTP \(httpResponse.statusCode)"
            }
            throw Allow2Error.apiError(message: message, code: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Allow2Error.invalidResponse
        }
    }
}

// MARK: - Internal Decodable helpers

/// Empty response placeholder for endpoints that return no meaningful body.
private struct EmptyResponse: Decodable {}

/// Response from POST /api/feedback/submit.
private struct FeedbackSubmitResponse: Decodable {
    let discussionId: UInt64
}

/// Response from POST /api/feedback/load.
private struct FeedbackLoadResponse: Decodable {
    let discussions: [FeedbackThread]
}

/// Response from POST /api/feedback/reply.
private struct FeedbackReplyResponse: Decodable {
    let messageId: UInt64
}
