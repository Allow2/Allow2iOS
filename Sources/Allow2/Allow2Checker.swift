import Foundation

/// Periodic check loop that calls the Allow2 API and tracks per-activity state.
///
/// Screen Time (activity 8) is the master quota -- always checked.
/// Gaming (3), Internet (1), Social (9) are independent sub-quotas.
/// The overall result is blocked if ANY checked activity is blocked.
/// The minimum remaining time across all checked activities is surfaced.
internal final class Allow2Checker {

    // MARK: - Constants

    private static let screenTimeActivityId: UInt64 = 8

    // MARK: - Dependencies

    private let api: any Allow2Api
    private let interval: TimeInterval

    // MARK: - Credentials (set by daemon)

    var userId: UInt64 = 0
    var pairId: UInt64 = 0
    var pairToken: String = ""
    var deviceToken: String = ""
    var childId: UInt64?

    /// Activities to check on each tick. Ensure Screen Time (8) is included.
    var activities: [ActivityCheck] = []

    // MARK: - Callbacks

    /// Called with the processed check result after each successful API call.
    var onCheckResult: ((CheckResult) -> Void)?

    /// Called when the API returns an error (network, timeout, etc.).
    var onError: ((Allow2Error) -> Void)?

    /// Called when the server returns HTTP 401 -- the device was released by the parent.
    var onCredentialsInvalidated: (() -> Void)?

    // MARK: - Internal state

    private var timer: Timer?
    private var running = false

    /// Per-activity previous state for detecting transitions.
    private var previousState: [UInt64: ActivityState] = [:]

    // MARK: - Init

    /// Create a checker with the given API client and polling interval.
    ///
    /// - Parameters:
    ///   - api: The API client conforming to `Allow2Api`.
    ///   - interval: Seconds between checks. Default is 30.
    init(api: any Allow2Api, interval: TimeInterval = 30) {
        self.api = api
        self.interval = interval
    }

    // MARK: - Lifecycle

    /// Start the repeating check timer. Performs an immediate check first.
    func start() {
        guard !running else { return }
        running = true

        // Immediate first check
        Task { await checkNow() }

        // Schedule repeating timer on the main run loop
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.checkNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stop the timer and cease checking.
    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    /// Perform an immediate check against the Allow2 API.
    func checkNow() async {
        guard running else { return }

        guard let childId = childId else {
            onError?(.missingChildId)
            return
        }

        let tz = TimeZone.current.identifier

        let request = CheckRequest(
            userId: userId,
            pairId: pairId,
            pairToken: pairToken,
            deviceToken: deviceToken,
            childId: childId,
            tz: tz,
            activities: activities,
            log: true
        )

        do {
            let result = try await api.check(request)
            processResult(result)
        } catch let error as Allow2Error {
            handleError(error)
        } catch {
            handleError(.networkError(error))
        }
    }

    /// Reset all tracked state. Call when the child changes or device unpairs.
    func reset() {
        previousState.removeAll()
    }

    // MARK: - Internal

    private func processResult(_ result: CheckResult) {
        // Update per-activity state and detect transitions
        for activity in result.activities {
            let prev = previousState[activity.id]
            let wasAllowed = prev?.allowed ?? true

            // Detect allowed -> blocked transition
            if wasAllowed && !activity.allowed {
                // State changed: this activity became blocked
            }

            // Update stored state
            previousState[activity.id] = ActivityState(
                allowed: activity.allowed,
                remaining: activity.remaining
            )
        }

        onCheckResult?(result)
    }

    private func handleError(_ error: Allow2Error) {
        switch error {
        case .notAuthorised:
            stop()
            onCredentialsInvalidated?()
        default:
            onError?(error)
        }
    }
}

// MARK: - Supporting types

/// Snapshot of a single activity's enforcement state.
private struct ActivityState {
    let allowed: Bool
    let remaining: Int?
}

// MARK: - Convenience

extension Allow2Checker {

    /// The minimum remaining seconds across all currently-allowed activities,
    /// or `nil` if no state has been received yet.
    var minimumRemaining: Int? {
        guard !previousState.isEmpty else { return nil }

        var minimum: Int?
        for (_, state) in previousState where state.allowed {
            guard let rem = state.remaining else { continue }
            if let current = minimum {
                minimum = min(current, rem)
            } else {
                minimum = rem
            }
        }
        return minimum
    }

    /// Whether ALL tracked activities are currently blocked.
    var allBlocked: Bool {
        guard !previousState.isEmpty else { return false }
        return previousState.values.allSatisfy { !$0.allowed }
    }
}
