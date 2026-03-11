import Foundation

/// Main orchestrator for the Allow2 Device SDK.
///
/// Manages the full device lifecycle:
///   1. **Unpaired** -- sits idle, waits for `initPairing` to start pairing
///   2. **Pairing**  -- pairing session active, polling for parent confirmation
///   3. **Paired**   -- paired but no child selected yet
///   4. **Enforcing** -- child selected, check loop running
///   5. **Parent**   -- parent mode, no enforcement
///
/// Usage:
/// ```swift
/// let daemon = Allow2Daemon(
///     deviceToken: "my-app-token",
///     activities: [ActivityCheck(activity: .screenTime), ActivityCheck(activity: .gaming)]
/// )
/// daemon.onCheckResult = { result in print(result) }
/// daemon.onWarning = { level, remaining in showWarning(level, remaining) }
/// await daemon.start()
/// ```
public final class Allow2Daemon: @unchecked Sendable {

    // MARK: - Public Types

    /// Lifecycle state of the daemon.
    public enum State: String, Sendable {
        case unpaired
        case pairing
        case paired
        case enforcing
        case parent
    }

    // MARK: - Public Properties

    /// The application-level device token identifying this product.
    public let deviceToken: String

    /// Server environment.
    public let environment: Allow2Environment

    /// Current lifecycle state.
    public private(set) var state: State = .unpaired

    /// Whether the device is currently paired.
    public var isPaired: Bool {
        return credentials != nil
    }

    /// Children on the paired account.
    public private(set) var children: [Allow2Child] = []

    /// Currently selected child (set via `selectChild` or automatic resolution).
    public private(set) var currentChild: Allow2Child?

    /// Activities to monitor during enforcement.
    public let activities: [ActivityCheck]

    /// Human-readable device name (shown to parent during pairing).
    public let deviceName: String

    // MARK: - Event Callbacks

    /// Called when paired state changes (true = paired, false = unpaired/released).
    public var onPairedStateChanged: ((Bool) -> Void)?

    /// Called after each successful permission check.
    public var onCheckResult: ((CheckResult) -> Void)?

    /// Called when the child is blocked or unblocked (bool = blocked, string = reason).
    public var onBlocked: ((Bool, String?) -> Void)?

    /// Called with progressive warnings (level + remaining seconds).
    public var onWarning: ((WarningLevel, Int) -> Void)?

    /// Called when credentials are invalidated (HTTP 401). Device is now unpaired.
    public var onCredentialsInvalidated: (() -> Void)?

    /// Called when the children list is refreshed.
    public var onChildrenUpdated: (([Allow2Child]) -> Void)?

    /// Called when interactive child selection is needed.
    public var onChildSelectRequired: (([Allow2Child]) -> Void)?

    /// Called when a check error occurs (non-fatal).
    public var onError: ((Allow2Error) -> Void)?

    // MARK: - Components

    /// The API client. Exposed for advanced usage (e.g., direct API calls).
    public let api: Allow2URLSessionApi

    /// Credential store for persisting pairing data.
    public let credentialStore: Allow2CredentialStore

    /// Child shield for PIN verification and rate limiting.
    public let childShield: Allow2ChildShield

    // Internal components
    private let checker: Allow2Checker
    private let warningController: Allow2WarningController
    private let offlineHandler: Allow2OfflineHandler
    private var pairingManager: Allow2PairingManager?
    private var requestManager: Allow2RequestManager?
    private var updatePoller: Allow2UpdatePoller?
    private var feedbackManager: Allow2FeedbackManager?

    // State
    private var credentials: Allow2PairedCredentials?
    private var running = false

    // MARK: - Configuration

    /// Check interval in seconds (default 30).
    public var checkInterval: TimeInterval = 30

    /// Offline grace period in seconds (default 300 = 5 minutes).
    public var gracePeriod: TimeInterval = 300

    /// Update poll interval in seconds (default 300 = 5 minutes).
    public var updateInterval: TimeInterval = 300

    // MARK: - Init

    /// Create a new Allow2 device daemon.
    ///
    /// - Parameters:
    ///   - deviceToken: Application-level token identifying this product.
    ///   - deviceName: Human-readable name shown to the parent during pairing.
    ///   - activities: Activities to monitor during enforcement.
    ///   - environment: Server environment (default: `.production`).
    ///   - credentialStore: Where to persist pairing credentials. Defaults to `KeychainCredentialStore`.
    public init(
        deviceToken: String,
        deviceName: String = "Allow2 Device",
        activities: [ActivityCheck],
        environment: Allow2Environment = .production,
        credentialStore: Allow2CredentialStore? = nil
    ) {
        self.deviceToken = deviceToken
        self.deviceName = deviceName
        self.activities = activities
        self.environment = environment

        #if canImport(Security)
        self.credentialStore = credentialStore ?? KeychainCredentialStore()
        #else
        guard let store = credentialStore else {
            fatalError("Allow2Daemon: credentialStore is required on platforms without Security framework")
        }
        self.credentialStore = store
        #endif

        self.api = Allow2URLSessionApi(deviceToken: deviceToken, environment: environment)
        self.childShield = Allow2ChildShield()
        self.checker = Allow2Checker(api: api, interval: 30)
        self.warningController = Allow2WarningController()
        self.offlineHandler = Allow2OfflineHandler(gracePeriod: 300)
    }

    // MARK: - Lifecycle

    /// Start the daemon. Loads stored credentials and begins enforcement if paired.
    public func start() async {
        guard !running else { return }
        running = true

        // Wire up checker callbacks
        wireCheckerCallbacks()

        // Wire up warning controller
        warningController.onWarningLevelChanged = { [weak self] level, remaining in
            self?.onWarning?(level, remaining)
        }

        // Load stored credentials
        credentials = credentialStore.load()

        if let creds = credentials {
            children = creds.children
            state = .paired
            await beginEnforcement()
        } else {
            state = .unpaired
        }
    }

    /// Stop the daemon. Cancels all running tasks and timers.
    public func stop() {
        running = false
        checker.stop()
        updatePoller?.stop()
        updatePoller = nil
        currentChild = nil

        if credentials != nil {
            state = .paired
        } else {
            state = .unpaired
        }
    }

    // MARK: - Pairing

    /// Initiate a pairing session.
    ///
    /// - Parameters:
    ///   - method: Pairing method (QR code or PIN code).
    /// - Returns: A `PairingSession` containing the PIN/QR data for display.
    public func initPairing(method: PairingMethod = .pinCode) async throws -> PairingSession {
        guard !isPaired else {
            throw Allow2Error.alreadyPaired
        }

        state = .pairing

        let manager = Allow2PairingManager(api: api, deviceToken: deviceToken)
        pairingManager = manager

        return try await manager.initPairing(deviceName: deviceName, method: method)
    }

    /// Poll the status of a pairing session.
    ///
    /// - Returns: The pairing status result. Check `completed` to know if pairing is done.
    public func checkPairingStatus(sessionId: String) async throws -> PairingStatusResult {
        guard let manager = pairingManager else {
            throw Allow2Error.notPaired
        }

        let result = try await manager.checkStatus(sessionId: sessionId)

        if result.completed,
           let userId = result.userId,
           let pairId = result.pairId,
           let pairToken = result.pairToken {

            let creds = Allow2PairedCredentials(
                userId: userId,
                pairId: pairId,
                pairToken: pairToken,
                children: result.children ?? []
            )
            try credentialStore.save(creds)
            credentials = creds
            children = creds.children
            state = .paired
            pairingManager = nil

            onPairedStateChanged?(true)
            onChildrenUpdated?(children)

            if running {
                await beginEnforcement()
            }
        }

        return result
    }

    /// Wait for pairing to complete (convenience polling wrapper).
    ///
    /// - Parameters:
    ///   - sessionId: The session ID from `initPairing`.
    ///   - pollInterval: Seconds between polls (default 2).
    ///   - timeout: Maximum seconds to wait (default 300).
    /// - Returns: The completed pairing result with credentials.
    public func waitForPairing(
        sessionId: String,
        pollInterval: TimeInterval = 2.0,
        timeout: TimeInterval = 300
    ) async throws -> PairingStatusResult {
        guard let manager = pairingManager else {
            throw Allow2Error.notPaired
        }

        let result = try await manager.waitForPairing(
            sessionId: sessionId,
            pollInterval: pollInterval,
            timeout: timeout
        )

        // Store credentials on completion
        if result.completed,
           let userId = result.userId,
           let pairId = result.pairId,
           let pairToken = result.pairToken {

            let creds = Allow2PairedCredentials(
                userId: userId,
                pairId: pairId,
                pairToken: pairToken,
                children: result.children ?? []
            )
            try credentialStore.save(creds)
            credentials = creds
            children = creds.children
            state = .paired
            pairingManager = nil

            onPairedStateChanged?(true)
            onChildrenUpdated?(children)

            if running {
                await beginEnforcement()
            }
        }

        return result
    }

    /// Called by the platform layer after pairing completes externally.
    public func onPairingComplete(_ creds: Allow2PairedCredentials) async {
        try? credentialStore.save(creds)
        credentials = creds
        children = creds.children
        state = .paired
        pairingManager = nil

        onPairedStateChanged?(true)
        onChildrenUpdated?(children)

        if running {
            await beginEnforcement()
        }
    }

    // MARK: - Child Management

    /// Select a child for enforcement with optional PIN verification.
    ///
    /// Uses `Allow2ChildShield` for PIN verification and rate limiting.
    ///
    /// - Parameters:
    ///   - childId: The child entity ID.
    ///   - pin: The child's PIN (required if child has a PIN set).
    /// - Throws: `Allow2ChildShieldError` on PIN failure or lockout.
    public func selectChild(_ childId: UInt64, pin: String = "") throws {
        // Verify PIN via child shield (handles lockout, rate limiting)
        try childShield.selectChild(childId, pin: pin, children: children)

        guard let child = children.first(where: { $0.id == childId }) else {
            throw Allow2Error.missingChildId
        }

        currentChild = child
        state = .enforcing
        warningController.reset()

        // Configure and start the checker
        configureChecker()
        checker.start()
    }

    /// Clear the current child selection. Stops enforcement and returns to paired state.
    public func clearCurrentChild() {
        checker.stop()
        checker.reset()
        warningController.reset()
        currentChild = nil
        state = .paired

        // Start update poller to keep credentials validated
        startUpdatePoller()
    }

    /// Enter parent mode. Stops all enforcement.
    public func enterParentMode() {
        checker.stop()
        checker.reset()
        warningController.reset()
        currentChild = nil
        state = .parent
    }

    // MARK: - Requests

    /// Create a "Request More Time" request on behalf of the current child.
    public func requestMoreTime(
        activityId: UInt64? = nil,
        minutes: Int,
        message: String? = nil
    ) async throws -> RequestResult {
        guard let creds = credentials else { throw Allow2Error.notPaired }
        guard let child = currentChild else { throw Allow2Error.missingChildId }

        let manager = getOrCreateRequestManager()
        return try await manager.createRequest(
            userId: creds.userId,
            pairId: creds.pairId,
            pairToken: creds.pairToken,
            childId: child.id,
            activityId: activityId,
            minutes: minutes,
            message: message
        )
    }

    /// Wait for a request to be resolved (approved/denied).
    public func waitForRequestResolution(
        requestId: UInt64,
        statusSecret: String,
        pollInterval: TimeInterval = 3.0,
        timeout: TimeInterval = 600
    ) async throws -> RequestStatus {
        let manager = getOrCreateRequestManager()
        return try await manager.waitForResolution(
            requestId: requestId,
            statusSecret: statusSecret,
            pollInterval: pollInterval,
            timeout: timeout
        )
    }

    // MARK: - Feedback

    /// Submit feedback to the developer.
    public func submitFeedback(
        category: FeedbackCategory,
        message: String,
        deviceContext: DeviceContext? = nil
    ) async throws -> UInt64 {
        guard let creds = credentials else { throw Allow2Error.notPaired }

        let manager = getOrCreateFeedbackManager()
        return try await manager.submitFeedback(
            userId: creds.userId,
            pairToken: creds.pairToken,
            pairId: creds.pairId,
            vid: 0, // Consumers should set this for their product
            childId: currentChild?.id,
            category: category,
            message: message,
            deviceContext: deviceContext ?? DeviceContext.current(
                sdkVersion: "2.0.0-alpha.1",
                productName: "Allow2 Swift SDK"
            )
        )
    }

    /// Load feedback threads for this device.
    public func loadFeedback() async throws -> [FeedbackThread] {
        guard let creds = credentials else { throw Allow2Error.notPaired }

        let manager = getOrCreateFeedbackManager()
        return try await manager.loadFeedback(
            userId: creds.userId,
            pairToken: creds.pairToken,
            pairId: creds.pairId
        )
    }

    // MARK: - Internal: Enforcement

    private func beginEnforcement() async {
        guard let creds = credentials else { return }

        // If only one child with no PIN, auto-select
        if children.count == 1, let only = children.first,
           only.pinHash == nil || (only.pinHash ?? "").isEmpty {
            currentChild = only
            state = .enforcing
            configureChecker()
            checker.start()
        } else if !children.isEmpty {
            // Interactive selection needed
            onChildSelectRequired?(children)
            startUpdatePoller()
        } else {
            // No children yet -- poll for updates
            startUpdatePoller()
        }

        // Start update poller for background refresh (extensions, bans, etc.)
        startUpdatePoller()
    }

    private func configureChecker() {
        guard let creds = credentials, let child = currentChild else { return }

        checker.stop()
        checker.reset()
        checker.userId = creds.userId
        checker.pairId = creds.pairId
        checker.pairToken = creds.pairToken
        checker.deviceToken = deviceToken
        checker.childId = child.id
        checker.activities = activities
    }

    private func wireCheckerCallbacks() {
        checker.onCheckResult = { [weak self] result in
            guard let self = self else { return }

            // Cache for offline use
            self.offlineHandler.cacheResult(result)

            // Process warnings
            self.warningController.processCheckResult(result)

            // Determine block status
            let blocked = !result.allowed
            let reason = result.activities
                .first(where: { !$0.allowed })?
                .name

            self.onBlocked?(blocked, blocked ? reason : nil)
            self.onCheckResult?(result)

            // Refresh children if returned
            if !result.children.isEmpty {
                self.children = result.children
                self.onChildrenUpdated?(result.children)
            }
        }

        checker.onError = { [weak self] error in
            self?.onError?(error)
        }

        checker.onCredentialsInvalidated = { [weak self] in
            self?.handleUnpaired()
        }
    }

    private func startUpdatePoller() {
        guard let creds = credentials else { return }

        if updatePoller == nil {
            updatePoller = Allow2UpdatePoller(api: api, interval: updateInterval)
        }

        updatePoller?.onChildrenUpdated = { [weak self] updatedChildren in
            guard let self = self else { return }
            self.children = updatedChildren

            // Persist updated children in credentials
            if var creds = self.credentials {
                creds.children = updatedChildren
                self.credentials = creds
                try? self.credentialStore.save(creds)
            }

            self.onChildrenUpdated?(updatedChildren)
        }

        updatePoller?.onExtension = { [weak self] ext in
            // Extension granted -- reset warning for that activity and force a check
            self?.warningController.resetActivity(ext.activity)
        }

        updatePoller?.onUnpaired = { [weak self] in
            self?.handleUnpaired()
        }

        updatePoller?.start(
            userId: creds.userId,
            pairId: creds.pairId,
            pairToken: creds.pairToken,
            deviceToken: deviceToken
        )
    }

    // MARK: - Internal: Helpers

    private func handleUnpaired() {
        checker.stop()
        checker.reset()
        updatePoller?.stop()
        updatePoller = nil
        warningController.reset()
        offlineHandler.clearCache()
        credentials = nil
        children = []
        currentChild = nil
        state = .unpaired

        try? credentialStore.clear()
        onPairedStateChanged?(false)
        onCredentialsInvalidated?()
    }

    private func getOrCreateRequestManager() -> Allow2RequestManager {
        if let existing = requestManager { return existing }
        let manager = Allow2RequestManager(api: api)
        requestManager = manager
        return manager
    }

    private func getOrCreateFeedbackManager() -> Allow2FeedbackManager {
        if let existing = feedbackManager { return existing }
        let manager = Allow2FeedbackManager(api: api)
        feedbackManager = manager
        return manager
    }
}
