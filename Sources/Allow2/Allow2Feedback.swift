import Foundation

// MARK: - Types

/// Feedback categories that match the server's valid categories.
///
/// These are the categories accepted by POST /api/feedback/submit.
/// The server validates against: bypass, missing_feature, not_working, question, other.
public enum FeedbackCategory: String, Sendable, CaseIterable {
    case bypass = "bypass"
    case missingFeature = "missing_feature"
    case notWorking = "not_working"
    case question = "question"
    case other = "other"
}

/// A feedback discussion thread between a parent/child and the developer.
public struct FeedbackThread: Codable, Identifiable, Sendable {
    /// Discussion ID.
    public let id: UInt64
    /// Description text (server-generated summary).
    public let description: String?
    /// Category of feedback (bypass, missing_feature, not_working, question, other).
    public let category: String?
    /// Product name associated with this feedback.
    public let productName: String?
    /// Whether the thread is resolved. `nil` means open.
    public let resolved: Int64?
    /// Timestamp when the thread was created (milliseconds since epoch).
    public let createdAt: Int64
    /// Version ID associated with this feedback.
    public let vid: UInt64?
    /// Web Service ID associated with this feedback.
    public let webServiceId: UInt64?
    /// Child ID that submitted this feedback.
    public let childId: UInt64?
    /// Name of the child who submitted this feedback.
    public let childName: String?
    /// Most recent message in the thread.
    public let latestMessage: FeedbackMessage?

    /// Whether this thread is still open (not resolved).
    public var isOpen: Bool {
        return resolved == nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case description
        case category
        case productName
        case resolved
        case createdAt
        case vid = "Vid"
        case webServiceId = "WebServiceId"
        case childId = "ChildId"
        case childName
        case latestMessage
    }
}

/// A single message within a feedback thread.
public struct FeedbackMessage: Codable, Sendable {
    /// Message ID.
    public let id: UInt64
    /// Message text content.
    public let text: String
    /// Timestamp when the message was created (milliseconds since epoch).
    public let createdAt: Int64

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
    }
}

/// Context about the device submitting feedback.
///
/// This is included in the feedback submission so the developer has diagnostic
/// context about the device/platform where the issue occurred.
public struct DeviceContext: Codable, Sendable {
    /// Human-readable device name (e.g. "Emma's MacBook").
    public let deviceName: String?
    /// Platform identifier (e.g. "iOS", "macOS", "linux").
    public let platform: String?
    /// SDK version string.
    public let sdkVersion: String?
    /// Product/app name (e.g. "Allow2 for iOS").
    public let productName: String?

    public init(
        deviceName: String? = nil,
        platform: String? = nil,
        sdkVersion: String? = nil,
        productName: String? = nil
    ) {
        self.deviceName = deviceName
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.productName = productName
    }

    /// Auto-populate a `DeviceContext` from the current device.
    ///
    /// Gathers platform and OS info using Foundation (no UIKit dependency).
    /// Pass `sdkVersion` and `productName` explicitly since those are app-specific.
    public static func current(
        sdkVersion: String? = nil,
        productName: String? = nil
    ) -> DeviceContext {
        let info = ProcessInfo.processInfo

        // Build platform string from OS info
        let osVersion = info.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        #if os(iOS)
        let platformName = "iOS"
        #elseif os(macOS)
        let platformName = "macOS"
        #elseif os(tvOS)
        let platformName = "tvOS"
        #elseif os(watchOS)
        let platformName = "watchOS"
        #elseif os(Linux)
        let platformName = "Linux"
        #else
        let platformName = "Unknown"
        #endif

        let platform = "\(platformName) \(osVersionString)"

        return DeviceContext(
            deviceName: info.hostName,
            platform: platform,
            sdkVersion: sdkVersion,
            productName: productName
        )
    }
}

// MARK: - API Protocol

/// Protocol for the API operations that feedback requires.
///
/// Authentication for feedback endpoints uses `feedbackDeviceAuth`:
/// the POST body includes `userId` + `pairToken` (and optionally `pairId`).
/// This is different from the main Device API which uses `deviceToken` + `format=json`.
public protocol Allow2FeedbackApi: Sendable {
    /// POST /api/feedback/submit
    func submitFeedback(
        userId: UInt64,
        pairToken: String,
        pairId: UInt64?,
        vid: UInt64,
        childId: UInt64?,
        category: FeedbackCategory,
        message: String,
        deviceContext: DeviceContext?
    ) async throws -> UInt64  // returns discussionId

    /// POST /api/feedback/load
    func loadFeedback(
        userId: UInt64,
        pairToken: String,
        pairId: UInt64?
    ) async throws -> [FeedbackThread]

    /// POST /api/feedback/reply
    func replyToFeedback(
        userId: UInt64,
        pairToken: String,
        discussionId: UInt64,
        message: String
    ) async throws -> UInt64  // returns messageId
}

// MARK: - Feedback Manager

/// Manages the feedback flow between a parent/child device and the Allow2 server.
///
/// Feedback is sent to the developer who registered the VID (Version ID).
/// The developer receives email and socket notifications and can reply
/// via the Developer Portal. Replies appear when `loadFeedback` is polled.
///
/// Authentication uses `feedbackDeviceAuth` which validates `userId` + `pairToken`
/// against the `PairedDevice` table. This is distinct from the main Device API auth
/// which requires `deviceToken` + `format=json`.
internal final class Allow2FeedbackManager: @unchecked Sendable {

    private let api: Allow2FeedbackApi

    // MARK: - Init

    init(api: Allow2FeedbackApi) {
        self.api = api
    }

    // MARK: - Public API

    /// Submit new feedback to the developer.
    ///
    /// Creates a Discussion (requestType='feedback') and the first Message on the server.
    /// The developer is notified via email and socket.
    ///
    /// - Parameters:
    ///   - userId: Controller account ID (from pairing).
    ///   - pairToken: Pairing token (from pairing). Used for `feedbackDeviceAuth`.
    ///   - pairId: Pairing ID (from pairing). Optional; `pairToken` alone suffices.
    ///   - vid: Version ID identifying this app/product.
    ///   - childId: Which child is submitting feedback, or `nil` if the parent.
    ///   - category: The feedback category.
    ///   - message: The feedback message text.
    ///   - deviceContext: Optional device/platform context for diagnostics.
    /// - Returns: The server-assigned discussion ID.
    func submitFeedback(
        userId: UInt64,
        pairToken: String,
        pairId: UInt64? = nil,
        vid: UInt64,
        childId: UInt64? = nil,
        category: FeedbackCategory,
        message: String,
        deviceContext: DeviceContext? = nil
    ) async throws -> UInt64 {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Allow2Error.apiError(message: "Message is required", code: nil)
        }

        return try await api.submitFeedback(
            userId: userId,
            pairToken: pairToken,
            pairId: pairId,
            vid: vid,
            childId: childId,
            category: category,
            message: message,
            deviceContext: deviceContext
        )
    }

    /// Load feedback threads for this user.
    ///
    /// Returns up to 50 most recent threads, including the latest message in each.
    /// Threads from granted accounts and linked child accounts are also included.
    ///
    /// - Parameters:
    ///   - userId: Controller account ID.
    ///   - pairToken: Pairing token for `feedbackDeviceAuth`.
    ///   - pairId: Pairing ID. Optional.
    /// - Returns: Array of feedback threads, newest first.
    func loadFeedback(
        userId: UInt64,
        pairToken: String,
        pairId: UInt64? = nil
    ) async throws -> [FeedbackThread] {
        return try await api.loadFeedback(
            userId: userId,
            pairToken: pairToken,
            pairId: pairId
        )
    }

    /// Reply to an existing feedback thread.
    ///
    /// Cannot reply to resolved threads (server returns an error).
    ///
    /// - Parameters:
    ///   - userId: Controller account ID.
    ///   - pairToken: Pairing token for `feedbackDeviceAuth`.
    ///   - discussionId: The thread to reply to.
    ///   - message: Reply message text.
    /// - Returns: The server-assigned message ID.
    func replyToFeedback(
        userId: UInt64,
        pairToken: String,
        discussionId: UInt64,
        message: String
    ) async throws -> UInt64 {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Allow2Error.apiError(message: "Message is required", code: nil)
        }

        return try await api.replyToFeedback(
            userId: userId,
            pairToken: pairToken,
            discussionId: discussionId,
            message: message
        )
    }
}
