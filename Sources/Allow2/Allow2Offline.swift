import Foundation

/// Handles offline operation by caching the last successful check result
/// and enforcing a configurable grace period.
///
/// **Policy**: During the grace period the cached result is used. After the
/// grace period expires, deny-by-default kicks in and a blocked `CheckResult`
/// is returned. This is a safety measure -- if the device cannot reach the
/// Allow2 API, it should not grant unlimited access.
internal final class Allow2OfflineHandler {

    // MARK: - Configuration

    /// How long (in seconds) the cached result is considered valid after the
    /// last successful API check. Default: 300 (5 minutes).
    let gracePeriod: TimeInterval

    // MARK: - Storage keys

    private let resultKey = "com.allow2.lastCheckResult"
    private let timestampKey = "com.allow2.lastCheckTimestamp"

    /// UserDefaults instance used for persistence.
    /// Using a suite allows tests to inject a custom instance.
    private let defaults: UserDefaults

    // MARK: - In-memory cache

    private var cachedResult: CheckResult?
    private var cachedTimestamp: Date?

    // MARK: - Init

    /// Create an offline handler.
    ///
    /// - Parameters:
    ///   - gracePeriod: Seconds before deny-by-default activates. Default 300.
    ///   - defaults: UserDefaults instance for persistence. Default is `.standard`.
    init(gracePeriod: TimeInterval = 300, defaults: UserDefaults = .standard) {
        self.gracePeriod = gracePeriod
        self.defaults = defaults
        loadFromDefaults()
    }

    // MARK: - Cache management

    /// Cache a successful check result in memory and persist to UserDefaults.
    ///
    /// - Parameter result: The check result to cache.
    func cacheResult(_ result: CheckResult) {
        cachedResult = result
        cachedTimestamp = Date()
        persistToDefaults(result)
    }

    /// Load the cached result. Returns `nil` if nothing is cached.
    func loadCachedResult() -> CheckResult? {
        return cachedResult
    }

    /// Whether we are currently in the grace period.
    ///
    /// Returns `true` if a cached result exists and was received less than
    /// `gracePeriod` seconds ago.
    func isInGracePeriod() -> Bool {
        guard let timestamp = cachedTimestamp else { return false }
        let elapsed = Date().timeIntervalSince(timestamp)
        return elapsed < gracePeriod
    }

    /// Seconds elapsed since the last successful check, or `nil` if no cache.
    func elapsedSinceLastCheck() -> TimeInterval? {
        guard let timestamp = cachedTimestamp else { return nil }
        return Date().timeIntervalSince(timestamp)
    }

    /// Return the appropriate check result for offline operation.
    ///
    /// - If within the grace period: returns the cached result.
    /// - If the grace period has expired (or no cache): returns a blocked result.
    func offlineCheckResult() -> CheckResult {
        if isInGracePeriod(), let cached = cachedResult {
            return cached
        }
        return Allow2OfflineHandler.blockedResult()
    }

    /// Clear all cached data. Call on unpair.
    func clearCache() {
        cachedResult = nil
        cachedTimestamp = nil
        defaults.removeObject(forKey: resultKey)
        defaults.removeObject(forKey: timestampKey)
    }

    // MARK: - Deny-by-default result

    /// Create a fully-blocked `CheckResult` used when offline and past grace period.
    static func blockedResult() -> CheckResult {
        return CheckResult(
            allowed: false,
            activities: [],
            dayTypes: DayTypesInfo(today: [], tomorrow: nil),
            children: [],
            subscription: SubscriptionInfo(active: false, type: nil, expires: nil),
            expires: nil
        )
    }

    // MARK: - Persistence (UserDefaults)

    private func persistToDefaults(_ result: CheckResult) {
        do {
            let data = try JSONEncoder().encode(result)
            defaults.set(data, forKey: resultKey)
            defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
        } catch {
            // Encoding failure is non-fatal -- memory cache still works
        }
    }

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: resultKey) else { return }
        let storedTimestamp = defaults.double(forKey: timestampKey)
        guard storedTimestamp > 0 else { return }

        do {
            let result = try JSONDecoder().decode(CheckResult.self, from: data)
            cachedResult = result
            cachedTimestamp = Date(timeIntervalSince1970: storedTimestamp)
        } catch {
            // Corrupt cache -- start fresh
            defaults.removeObject(forKey: resultKey)
            defaults.removeObject(forKey: timestampKey)
        }
    }
}
