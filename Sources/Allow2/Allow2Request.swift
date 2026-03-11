import Foundation

// MARK: - Types

/// Result of creating a "Request More Time" request.
public struct RequestResult: Codable, Sendable {
    /// Whether the request was successfully sent to the server.
    public let requestSent: Bool
    /// Server-assigned request identifier (present when sent).
    public let requestId: UInt64?
    /// Secret token used to poll the request status without authentication.
    public let statusSecret: String?

    public init(
        requestSent: Bool,
        requestId: UInt64? = nil,
        statusSecret: String? = nil
    ) {
        self.requestSent = requestSent
        self.requestId = requestId
        self.statusSecret = statusSecret
    }
}

/// Current status of a "Request More Time" request.
public enum RequestStatus: String, Codable, Sendable {
    case pending
    case approved
    case denied
    case expired
}

/// Detailed response from a request status poll.
public struct RequestStatusResult: Codable, Sendable {
    /// Current status of the request.
    public let status: RequestStatus
    /// Additional minutes granted (present when approved).
    public let extension_: Int?

    public init(status: RequestStatus, extension_: Int? = nil) {
        self.status = status
        self.extension_ = extension_
    }
}

// MARK: - API Protocol

/// Minimal protocol for the API operations that request management requires.
public protocol Allow2RequestApi: Sendable {
    /// POST /api/request/createRequest
    func createRequest(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        childId: UInt64,
        activityId: UInt64?,
        minutes: Int,
        message: String?
    ) async throws -> RequestResult

    /// GET /api/request/{requestId}/status (with X-Status-Secret header)
    func getRequestStatus(
        requestId: UInt64,
        statusSecret: String
    ) async throws -> RequestStatusResult
}

// MARK: - Request Manager

/// Manages the "Request More Time" flow for a child.
///
/// Flow:
/// 1. Child triggers a request (from block screen or warning banner).
/// 2. `createRequest` sends the request to the Allow2 server.
/// 3. Server notifies the parent via push notification.
/// 4. `waitForResolution` polls until the parent approves, denies, or timeout.
///
/// The `statusSecret` returned on creation is used for unauthenticated polling,
/// so the child device does not need full credentials to check status.
internal final class Allow2RequestManager: @unchecked Sendable {

    private let api: Allow2RequestApi

    /// Tracks the active polling task so it can be cancelled.
    private var activePollTask: Task<RequestStatus, Error>?

    /// Lock protecting mutable state.
    private let lock = NSLock()

    // MARK: - Init

    init(api: Allow2RequestApi) {
        self.api = api
    }

    // MARK: - Public API

    /// Create a request for more time.
    ///
    /// - Parameters:
    ///   - userId: Controller account ID (from pairing).
    ///   - pairId: Pairing ID (from pairing).
    ///   - pairToken: Pairing token (from pairing).
    ///   - childId: Which child is requesting.
    ///   - activityId: Which activity to request time for, or `nil` for general screen time.
    ///   - minutes: Number of minutes requested.
    ///   - message: Optional message from the child to the parent.
    /// - Returns: A `RequestResult` containing the request ID and status secret for polling.
    func createRequest(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        childId: UInt64,
        activityId: UInt64? = nil,
        minutes: Int,
        message: String? = nil
    ) async throws -> RequestResult {
        return try await api.createRequest(
            userId: userId,
            pairId: pairId,
            pairToken: pairToken,
            childId: childId,
            activityId: activityId,
            minutes: minutes,
            message: message
        )
    }

    /// Poll the request status once.
    ///
    /// - Parameters:
    ///   - requestId: The request ID from `createRequest`.
    ///   - statusSecret: The status secret from `createRequest`.
    /// - Returns: The current request status.
    func checkRequestStatus(
        requestId: UInt64,
        statusSecret: String
    ) async throws -> RequestStatus {
        let result = try await api.getRequestStatus(
            requestId: requestId,
            statusSecret: statusSecret
        )
        return result.status
    }

    /// Poll until the request is resolved (approved/denied) or times out.
    ///
    /// This is a convenience wrapper that repeatedly calls `checkRequestStatus`
    /// with `Task.sleep` between polls. Supports cooperative cancellation
    /// via Swift structured concurrency.
    ///
    /// - Parameters:
    ///   - requestId: The request ID from `createRequest`.
    ///   - statusSecret: The status secret from `createRequest`.
    ///   - pollInterval: Seconds between status checks (default 3.0).
    ///   - timeout: Maximum seconds to wait (default 600 = 10 minutes).
    /// - Returns: The final `RequestStatus` (.approved or .denied).
    /// - Throws: `Allow2Error.timeout` if the timeout is reached.
    func waitForResolution(
        requestId: UInt64,
        statusSecret: String,
        pollInterval: TimeInterval = 3.0,
        timeout: TimeInterval = 600
    ) async throws -> RequestStatus {
        // Cancel any previous polling task
        cancelActivePolling()

        let task = Task<RequestStatus, Error> { [weak self] in
            guard let self else {
                throw Allow2Error.timeout
            }

            let deadline = Date().addingTimeInterval(timeout)
            let sleepNanoseconds = UInt64(pollInterval * 1_000_000_000)

            while true {
                try Task.checkCancellation()

                if Date() >= deadline {
                    throw Allow2Error.timeout
                }

                do {
                    let status = try await self.checkRequestStatus(
                        requestId: requestId,
                        statusSecret: statusSecret
                    )

                    switch status {
                    case .approved, .denied, .expired:
                        return status
                    case .pending:
                        break // continue polling
                    }
                } catch is CancellationError {
                    throw Allow2Error.timeout
                } catch let error as Allow2Error {
                    // HTTP 401 is terminal -- device unpaired
                    if case .notAuthorised = error {
                        throw error
                    }
                    // Other errors are transient -- continue polling
                } catch {
                    // Network errors are transient -- continue polling
                }

                try await Task.sleep(nanoseconds: sleepNanoseconds)
            }
        }

        lock.lock()
        activePollTask = task
        lock.unlock()

        do {
            let result = try await task.value
            clearActivePolling()
            return result
        } catch {
            clearActivePolling()
            throw error
        }
    }

    /// Cancel any active polling loop.
    func cancelPolling() {
        cancelActivePolling()
    }

    // MARK: - Private

    private func cancelActivePolling() {
        lock.lock()
        activePollTask?.cancel()
        activePollTask = nil
        lock.unlock()
    }

    private func clearActivePolling() {
        lock.lock()
        activePollTask = nil
        lock.unlock()
    }
}
