import Foundation

// MARK: - Types

/// Update events returned by the getUpdates endpoint.
///
/// The server returns delta updates since `timestampMillis`, including:
/// extensions (parent approved extra time), day type changes, quota updates,
/// bans, and refreshed children lists.
public struct Allow2UpdateResult: Codable, Sendable {
    /// Server timestamp for the next delta poll.
    public let timestampMillis: Int64?

    /// Extensions granted by parent (extra time approved).
    public let extensions: [ExtensionUpdate]

    /// Day type changes (e.g. school day switched to holiday).
    public let dayTypeChanges: [DayTypeChange]

    /// Quota updates (daily limit changed).
    public let quotaUpdates: [QuotaUpdate]

    /// Bans (activity banned or unbanned).
    public let bans: [BanUpdate]

    /// Refreshed children list (names, PINs, added/removed children).
    public let children: [Allow2Child]

    public init(
        timestampMillis: Int64? = nil,
        extensions: [ExtensionUpdate] = [],
        dayTypeChanges: [DayTypeChange] = [],
        quotaUpdates: [QuotaUpdate] = [],
        bans: [BanUpdate] = [],
        children: [Allow2Child] = []
    ) {
        self.timestampMillis = timestampMillis
        self.extensions = extensions
        self.dayTypeChanges = dayTypeChanges
        self.quotaUpdates = quotaUpdates
        self.bans = bans
        self.children = children
    }
}

/// An extension (extra time) granted by the parent.
public struct ExtensionUpdate: Codable, Sendable {
    public let childId: UInt64
    public let activity: UInt64
    public let additionalMinutes: Int
}

/// A day type change for a child (e.g. school day to weekend).
public struct DayTypeChange: Codable, Sendable {
    public let childId: UInt64
    public let dayType: String
}

/// A quota (daily limit) update for a child's activity.
public struct QuotaUpdate: Codable, Sendable {
    public let childId: UInt64
    public let activity: UInt64
    public let newQuota: Int
}

/// A ban/unban event for a child's activity.
public struct BanUpdate: Codable, Sendable {
    public let childId: UInt64
    public let activity: UInt64
    public let banned: Bool
}

// MARK: - API Protocol

/// Minimal protocol for the API operations that update polling requires.
public protocol Allow2UpdatesApi: Sendable {
    /// GET /api/getUpdates with query parameters.
    func getUpdates(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        deviceToken: String,
        timestampMillis: Int64?
    ) async throws -> Allow2UpdateResult
}

// MARK: - Update Poller

/// Polls the Allow2 server for updates (extensions, day type changes,
/// quota updates, bans, children list refreshes).
///
/// The poller uses delta timestamps so that each poll only returns changes
/// since the last successful poll. On HTTP 401, the device should be
/// considered unpaired and the poller stops automatically.
///
/// Usage:
/// ```swift
/// let poller = Allow2UpdatePoller(api: myApi, interval: 300)
/// poller.onChildrenUpdated = { children in
///     // Refresh child list
/// }
/// poller.onExtension = { ext in
///     // Child got extra time
/// }
/// poller.onUnpaired = {
///     // Device was released -- clear credentials
/// }
/// poller.start(userId: u, pairId: p, pairToken: t, deviceToken: d)
/// ```
internal final class Allow2UpdatePoller: @unchecked Sendable {

    private let api: Allow2UpdatesApi
    private let interval: TimeInterval

    /// Last server timestamp for delta polling.
    private var lastTimestamp: Int64?

    /// The active polling task.
    private var pollTask: Task<Void, Never>?

    /// Lock protecting mutable state.
    private let lock = NSLock()

    // MARK: - Callbacks

    /// Called when the children list is refreshed.
    var onChildrenUpdated: (([Allow2Child]) -> Void)?

    /// Called when an extension (extra time) is granted.
    var onExtension: ((ExtensionUpdate) -> Void)?

    /// Called when a day type changes for a child.
    var onDayTypeChanged: ((DayTypeChange) -> Void)?

    /// Called when a quota is updated for a child's activity.
    var onQuotaUpdated: ((QuotaUpdate) -> Void)?

    /// Called when an activity is banned/unbanned for a child.
    var onBan: ((BanUpdate) -> Void)?

    /// Called on HTTP 401 -- device has been unpaired. Poller stops automatically.
    var onUnpaired: (() -> Void)?

    /// Called when a polling error occurs (non-terminal).
    var onError: ((Error) -> Void)?

    // MARK: - Init

    /// Create an update poller.
    ///
    /// - Parameters:
    ///   - api: API implementation conforming to `Allow2UpdatesApi`.
    ///   - interval: Seconds between polls (default 300 = 5 minutes).
    init(api: Allow2UpdatesApi, interval: TimeInterval = 300) {
        self.api = api
        self.interval = interval
    }

    // MARK: - Public API

    /// Start polling with the given device credentials.
    ///
    /// If already polling, this is a no-op. Call `stop()` first to restart
    /// with different credentials.
    func start(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        deviceToken: String
    ) {
        lock.lock()
        guard pollTask == nil else {
            lock.unlock()
            return
        }

        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }

            // Immediate first poll, then sleep between subsequent polls
            while !Task.isCancelled {
                await self.performPoll(
                    userId: userId,
                    pairId: pairId,
                    pairToken: pairToken,
                    deviceToken: deviceToken
                )

                // Check if we were stopped during the poll
                if Task.isCancelled { break }

                // Sleep between polls
                let sleepNanoseconds = UInt64(self.interval * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    break // Cancelled during sleep
                }
            }
        }

        pollTask = task
        lock.unlock()
    }

    /// Stop polling.
    func stop() {
        lock.lock()
        pollTask?.cancel()
        pollTask = nil
        lock.unlock()
    }

    /// Perform a single poll immediately (for manual refresh).
    ///
    /// This does not affect the automatic polling schedule.
    func pollNow(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        deviceToken: String
    ) async {
        await performPoll(
            userId: userId,
            pairId: pairId,
            pairToken: pairToken,
            deviceToken: deviceToken
        )
    }

    // MARK: - Private

    private func performPoll(
        userId: UInt64,
        pairId: UInt64,
        pairToken: String,
        deviceToken: String
    ) async {
        do {
            let result = try await api.getUpdates(
                userId: userId,
                pairId: pairId,
                pairToken: pairToken,
                deviceToken: deviceToken,
                timestampMillis: lastTimestamp
            )

            // Advance timestamp for delta polling
            if let ts = result.timestampMillis {
                lock.lock()
                lastTimestamp = ts
                lock.unlock()
            }

            processUpdates(result)
        } catch {
            handleError(error)
        }
    }

    private func processUpdates(_ result: Allow2UpdateResult) {
        // Extensions -- parent approved extra time
        for ext in result.extensions {
            onExtension?(ext)
        }

        // Day type changes
        for change in result.dayTypeChanges {
            onDayTypeChanged?(change)
        }

        // Quota updates
        for update in result.quotaUpdates {
            onQuotaUpdated?(update)
        }

        // Bans
        for ban in result.bans {
            onBan?(ban)
        }

        // Children list refresh
        if !result.children.isEmpty {
            onChildrenUpdated?(result.children)
        }
    }

    private func handleError(_ error: Error) {
        // HTTP 401 means the device has been unpaired
        if let allow2Error = error as? Allow2Error {
            if case .notAuthorised = allow2Error {
                stop()
                onUnpaired?()
                return
            }
        }

        onError?(error)
    }
}
