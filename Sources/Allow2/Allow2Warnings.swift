import Foundation

/// Progressive warning levels based on remaining time.
///
/// Warnings fire ONCE per level transition. When remaining time drops below
/// a threshold, the corresponding level fires and will not fire again until
/// the warning controller is reset (e.g., child changes, time is granted).
public enum WarningLevel: Int, Comparable, Sendable, CaseIterable {
    case none            = 0
    case fifteenMinutes  = 1    // 900s
    case fiveMinutes     = 2    // 300s
    case oneMinute       = 3    // 60s
    case thirtySeconds   = 4    // 30s
    case tenSeconds      = 5    // 10s
    case blocked         = 6    // 0s

    public static func < (lhs: WarningLevel, rhs: WarningLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Determine the warning level for a given number of remaining seconds.
    ///
    /// - Parameter seconds: Remaining seconds until the activity is blocked.
    /// - Returns: The appropriate `WarningLevel`.
    public static func forRemainingSeconds(_ seconds: Int) -> WarningLevel {
        if seconds <= 0   { return .blocked }
        if seconds <= 10  { return .tenSeconds }
        if seconds <= 30  { return .thirtySeconds }
        if seconds <= 60  { return .oneMinute }
        if seconds <= 300 { return .fiveMinutes }
        if seconds <= 900 { return .fifteenMinutes }
        return .none
    }
}

/// Manages progressive time-remaining warnings.
///
/// Processes check results and invokes a callback when the warning level
/// increases. Each level fires at most once per activity until `reset()` or
/// `resetActivity(_:)` is called. This prevents spamming the user with
/// repeated warnings for the same threshold.
internal final class Allow2WarningController {

    // MARK: - Configuration

    /// Thresholds in descending order of remaining seconds.
    /// The default set matches the `WarningLevel` enum values.
    var thresholds: [Int] = [900, 300, 60, 30, 10]

    // MARK: - Callback

    /// Called when a NEW warning level is reached for any activity.
    ///
    /// - Parameters:
    ///   - level: The new `WarningLevel`.
    ///   - remainingSeconds: Actual remaining seconds at the time of the transition.
    var onWarningLevelChanged: ((WarningLevel, Int) -> Void)?

    // MARK: - State

    /// The highest warning level that has been emitted.
    /// Tracked globally (not per-activity) so that the consumer sees a
    /// single escalating sequence.
    private(set) var lastLevel: WarningLevel = .none

    /// Per-activity tracking of which warning levels have already fired.
    /// Key: activity ID, Value: set of `WarningLevel` raw values already emitted.
    private var firedLevels: [UInt64: Set<Int>] = [:]

    // MARK: - Processing

    /// Process a check result and emit warnings for any newly crossed thresholds.
    ///
    /// Call this after every successful API check.
    ///
    /// - Parameter result: The decoded `CheckResult` from the API.
    func processCheckResult(_ result: CheckResult) {
        for activity in result.activities {
            guard activity.allowed else {
                // Activity is already blocked -- emit blocked-level warning once
                emitIfNew(activityId: activity.id, level: .blocked, remaining: 0)
                continue
            }

            guard let remaining = activity.remaining else {
                // Unlimited time -- no warnings needed
                continue
            }

            let level = WarningLevel.forRemainingSeconds(remaining)
            if level == .none { continue }

            emitIfNew(activityId: activity.id, level: level, remaining: remaining)
        }
    }

    /// Reset warning state for a specific activity.
    ///
    /// Call when more time is granted or the activity state is refreshed.
    ///
    /// - Parameter activityId: The activity to reset.
    func resetActivity(_ activityId: UInt64) {
        firedLevels.removeValue(forKey: activityId)
        recalculateLastLevel()
    }

    /// Reset all warning state.
    ///
    /// Call when the child changes or the session ends.
    func reset() {
        firedLevels.removeAll()
        lastLevel = .none
    }

    // MARK: - Internal

    private func emitIfNew(activityId: UInt64, level: WarningLevel, remaining: Int) {
        var fired = firedLevels[activityId] ?? Set<Int>()

        // Emit this level and all levels below it that haven't fired yet.
        // This handles cases where remaining jumps past multiple thresholds
        // between checks (e.g., from 400s straight to 20s).
        var didEmitNew = false
        for candidate in WarningLevel.allCases where candidate != .none {
            if candidate <= level && !fired.contains(candidate.rawValue) {
                fired.insert(candidate.rawValue)
                didEmitNew = true
            }
        }

        firedLevels[activityId] = fired

        // Only invoke the callback for the highest new level
        if didEmitNew && level > lastLevel {
            lastLevel = level
            onWarningLevelChanged?(level, remaining)
        } else if didEmitNew {
            // New level for this activity, but not higher than global lastLevel.
            // Still notify so the consumer can show per-activity warnings.
            onWarningLevelChanged?(level, remaining)
        }
    }

    private func recalculateLastLevel() {
        var highest: WarningLevel = .none
        for (_, fired) in firedLevels {
            for raw in fired {
                if let level = WarningLevel(rawValue: raw), level > highest {
                    highest = level
                }
            }
        }
        lastLevel = highest
    }
}
