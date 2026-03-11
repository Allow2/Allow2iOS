import Foundation

// MARK: - Types

/// Method used for device pairing. Parent scans QR or enters PIN on their phone.
/// The device NEVER handles parent credentials.
public enum PairingMethod: String, Sendable {
    case qrCode = "qr"
    case pinCode = "pin"
}

/// Represents an active pairing session awaiting parent confirmation.
public struct PairingSession: Codable, Sendable {
    /// Server-assigned session identifier.
    public let sessionId: String
    /// Base64-encoded QR image data (present when method is `.qrCode`).
    public let qrCodeData: String?
    /// URL encoded in the QR code for deep linking into the Allow2 app.
    public let webPairingUrl: String?
    /// Server-assigned 6-digit PIN (present when method is `.pinCode`).
    public let pinCode: String?

    public init(
        sessionId: String,
        qrCodeData: String? = nil,
        webPairingUrl: String? = nil,
        pinCode: String? = nil
    ) {
        self.sessionId = sessionId
        self.qrCodeData = qrCodeData
        self.webPairingUrl = webPairingUrl
        self.pinCode = pinCode
    }
}

/// Result returned when pairing completes (parent confirmed on their device).
public struct PairingStatusResult: Codable, Sendable {
    /// Whether the parent has completed pairing.
    public let completed: Bool
    /// Controller's user ID (present when completed).
    public let userId: UInt64?
    /// Pairing ID for subsequent API calls (present when completed).
    public let pairId: UInt64?
    /// Pairing token for authentication (present when completed).
    public let pairToken: String?
    /// Children on the controller's account (present when completed).
    public let children: [Allow2Child]?

    public init(
        completed: Bool,
        userId: UInt64? = nil,
        pairId: UInt64? = nil,
        pairToken: String? = nil,
        children: [Allow2Child]? = nil
    ) {
        self.completed = completed
        self.userId = userId
        self.pairId = pairId
        self.pairToken = pairToken
        self.children = children
    }
}

// MARK: - Errors

/// Errors specific to the pairing flow.
public enum Allow2PairingError: Error, Sendable {
    /// The server returned an unexpected response during pairing init.
    case initFailed(String)
    /// Polling for pairing status failed.
    case statusCheckFailed(String)
    /// Pairing timed out waiting for parent confirmation.
    case timeout
    /// Pairing was cancelled by the caller.
    case cancelled
    /// The session was not found or has expired on the server.
    case sessionExpired
    /// Missing required fields in the server response.
    case invalidResponse(String)
}

// MARK: - API Protocol

/// Minimal protocol for the API operations that pairing requires.
/// The full `Allow2Api` implementation is expected to conform to this.
public protocol Allow2PairingApi: Sendable {
    /// POST /api/pair/init — Register a new pairing session.
    func initPairing(
        deviceToken: String,
        deviceName: String,
        method: PairingMethod
    ) async throws -> PairingSession

    /// POST /api/pair/status — Check whether the parent has confirmed.
    func checkPairingStatus(sessionId: String) async throws -> PairingStatusResult

    /// POST /api/pair/cancel — Cancel an active pairing session.
    func cancelPairing(sessionId: String) async throws
}

// MARK: - Pairing Manager

/// Manages the device-side pairing flow.
///
/// Flow:
/// 1. Device calls `initPairing` to register a session and get a PIN/QR.
/// 2. Device displays PIN or QR code to the user.
/// 3. Parent opens Allow2 app on their phone, enters PIN or scans QR.
/// 4. Device polls `checkStatus` (or uses `waitForPairing` convenience).
/// 5. On confirmation, receives credentials (userId, pairId, pairToken, children).
///
/// The device NEVER handles parent credentials. Parents authenticate
/// exclusively on their own phone/app.
internal final class Allow2PairingManager: @unchecked Sendable {

    private let api: Allow2PairingApi
    private let deviceToken: String

    /// Tracks whether a `waitForPairing` loop is active, so it can be cancelled.
    private var activePollTask: Task<PairingStatusResult, Error>?

    /// Lock protecting mutable state.
    private let lock = NSLock()

    // MARK: - Init

    init(api: Allow2PairingApi, deviceToken: String) {
        self.api = api
        self.deviceToken = deviceToken
    }

    // MARK: - Public API

    /// Start a new pairing session. The device should display the returned
    /// QR code or PIN to the user.
    ///
    /// - Parameters:
    ///   - deviceName: Human-readable name shown to the parent (e.g. "Living Room PC").
    ///   - method: Whether to use QR code or PIN code pairing.
    /// - Returns: A `PairingSession` containing the session ID and display data.
    func initPairing(
        deviceName: String,
        method: PairingMethod = .pinCode
    ) async throws -> PairingSession {
        let session = try await api.initPairing(
            deviceToken: deviceToken,
            deviceName: deviceName,
            method: method
        )

        guard !session.sessionId.isEmpty else {
            throw Allow2PairingError.initFailed("Server returned empty session ID")
        }

        return session
    }

    /// Poll the server once for pairing completion.
    ///
    /// - Parameter sessionId: The session ID returned from `initPairing`.
    /// - Returns: The current pairing status.
    func checkStatus(sessionId: String) async throws -> PairingStatusResult {
        let result = try await api.checkPairingStatus(sessionId: sessionId)

        // Validate completed results have required fields
        if result.completed {
            guard result.userId != nil,
                  result.pairId != nil,
                  result.pairToken != nil else {
                throw Allow2PairingError.invalidResponse(
                    "Pairing marked complete but missing userId, pairId, or pairToken"
                )
            }
        }

        return result
    }

    /// Cancel an active pairing session on the server.
    ///
    /// - Parameter sessionId: The session ID to cancel.
    func cancelPairing(sessionId: String) async throws {
        // Cancel any active polling loop first
        cancelActivePolling()
        try await api.cancelPairing(sessionId: sessionId)
    }

    /// Poll until pairing completes or the timeout is reached.
    ///
    /// This is a convenience wrapper that repeatedly calls `checkStatus`
    /// with `Task.sleep` between polls. It supports cooperative cancellation
    /// via Swift structured concurrency.
    ///
    /// - Parameters:
    ///   - sessionId: The session ID returned from `initPairing`.
    ///   - pollInterval: Seconds between status checks (default 2.0).
    ///   - timeout: Maximum seconds to wait before throwing `.timeout` (default 300).
    /// - Returns: The completed `PairingStatusResult` with credentials.
    func waitForPairing(
        sessionId: String,
        pollInterval: TimeInterval = 2.0,
        timeout: TimeInterval = 300
    ) async throws -> PairingStatusResult {
        // Cancel any previous polling task
        cancelActivePolling()

        let task = Task<PairingStatusResult, Error> { [weak self] in
            guard let self else {
                throw Allow2PairingError.cancelled
            }

            let deadline = Date().addingTimeInterval(timeout)
            let sleepNanoseconds = UInt64(pollInterval * 1_000_000_000)

            while true {
                // Check cancellation
                try Task.checkCancellation()

                // Check timeout
                if Date() >= deadline {
                    throw Allow2PairingError.timeout
                }

                do {
                    let result = try await self.checkStatus(sessionId: sessionId)
                    if result.completed {
                        return result
                    }
                } catch is CancellationError {
                    throw Allow2PairingError.cancelled
                } catch let error as Allow2PairingError {
                    // Session expired is terminal
                    if case .sessionExpired = error {
                        throw error
                    }
                    // Other pairing errors during polling are transient -- continue
                } catch {
                    // Network errors etc are transient -- continue polling
                }

                // Sleep between polls
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
