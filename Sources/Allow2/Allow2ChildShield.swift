import Foundation
import CryptoKit

// MARK: - Errors

/// Errors from the child shield PIN verification flow.
public enum Allow2ChildShieldError: Error, Sendable {
    /// The child ID was not found in the children list.
    case childNotFound(UInt64)
    /// The child account is locked out due to too many failed PIN attempts.
    case lockedOut(remainingSeconds: Int)
    /// The PIN was incorrect.
    case incorrectPin(failedAttempts: Int)
    /// The child has no PIN configured (pinHash or pinSalt is nil).
    case noPinConfigured(UInt64)
}

// MARK: - Child Shield

/// PIN verification and rate limiting for child identification.
///
/// When a device boots or resumes, the child must identify themselves.
/// If the child has a PIN configured, this class verifies it using the
/// same SHA-256 + salt algorithm as the server, the Node SDK, and the
/// Brave C++ implementation.
///
/// Hash algorithm (must be identical across all platforms):
///   `SHA256(pin + salt)` where both pin and salt are UTF-8 strings,
///   producing a lowercase hex-encoded digest.
///
/// Rate limiting uses progressive lockout matching the Brave browser:
///   - 3 consecutive failures:  30 second lockout
///   - 6 consecutive failures:  60 second lockout
///   - 9 consecutive failures:  5 minute (300s) lockout
///   - 12+ consecutive failures: 15 minute (900s) lockout
///
/// This class is thread-safe via `NSLock`. It intentionally avoids any
/// UIKit/SwiftUI imports so it can be used on any Apple platform or
/// even Linux (with swift-crypto).
public final class Allow2ChildShield: @unchecked Sendable {

    // MARK: - Lockout thresholds (matching Brave)

    private static let lockoutProgression: [(threshold: Int, duration: TimeInterval)] = [
        (3,  30),    // 3 failures  -> 30 seconds
        (6,  60),    // 6 failures  -> 60 seconds
        (9,  300),   // 9 failures  -> 5 minutes
        (12, 900),   // 12 failures -> 15 minutes
    ]

    // MARK: - State

    /// Number of consecutive failed PIN attempts per child.
    private var failedAttempts: [UInt64: Int] = [:]

    /// Lockout expiry time per child.
    private var lockoutUntil: [UInt64: Date] = [:]

    private let lock = NSLock()

    // MARK: - Init

    public init() {}

    // MARK: - PIN Hashing

    /// Hash a PIN with the given salt using SHA-256.
    ///
    /// The algorithm is: `SHA256(pin + salt)` producing a lowercase hex string.
    /// This MUST match the server, the Node SDK (`createHash('sha256').update(pin + salt).digest('hex')`),
    /// and the Brave C++ implementation.
    ///
    /// - Parameters:
    ///   - pin: The raw PIN string (typically 4-6 digits).
    ///   - salt: The hex-encoded salt string from the server.
    /// - Returns: Lowercase hex-encoded SHA-256 digest.
    public static func hashPin(_ pin: String, salt: String) -> String {
        let input = pin + salt
        let inputData = Data(input.utf8)
        let digest = SHA256.hash(data: inputData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - PIN Verification

    /// Verify a PIN against a child's stored hash and salt.
    ///
    /// Uses constant-time comparison to prevent timing attacks.
    ///
    /// - Parameters:
    ///   - pin: The raw PIN entered by the user.
    ///   - child: The child whose PIN to verify.
    /// - Returns: `true` if the PIN matches, `false` if the child has no PIN
    ///   configured or the PIN does not match.
    public func verifyPin(_ pin: String, for child: Allow2Child) -> Bool {
        guard let storedHash = child.pinHash,
              let salt = child.pinSalt,
              !storedHash.isEmpty,
              !salt.isEmpty else {
            // No PIN configured -- treat as honour system (allow)
            return true
        }

        let computed = Self.hashPin(pin, salt: salt)
        return constantTimeEqual(computed, storedHash)
    }

    // MARK: - Lockout

    /// Check if a child is currently locked out from PIN entry.
    ///
    /// - Parameter childId: The child's ID.
    /// - Returns: A tuple of whether the child is locked and how many seconds remain.
    public func isLockedOut(_ childId: UInt64) -> (locked: Bool, remainingSeconds: Int) {
        lock.lock()
        defer { lock.unlock() }
        return _isLockedOut(childId)
    }

    /// Record a failed PIN attempt for a child.
    ///
    /// Returns the lockout duration in seconds if a lockout was triggered,
    /// or 0 if the child is not yet locked out.
    ///
    /// - Parameter childId: The child's ID.
    /// - Returns: Lockout duration in seconds (0 if no lockout triggered).
    @discardableResult
    public func recordFailedAttempt(_ childId: UInt64) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let current = (failedAttempts[childId] ?? 0) + 1
        failedAttempts[childId] = current

        // Find the highest matching lockout threshold
        var lockoutDuration: TimeInterval = 0
        for entry in Self.lockoutProgression {
            if current >= entry.threshold {
                lockoutDuration = entry.duration
            }
        }

        if lockoutDuration > 0 {
            lockoutUntil[childId] = Date().addingTimeInterval(lockoutDuration)
            return Int(lockoutDuration)
        }

        return 0
    }

    /// Clear lockout and failed attempts on successful PIN entry.
    ///
    /// - Parameter childId: The child's ID.
    public func clearLockout(_ childId: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        failedAttempts.removeValue(forKey: childId)
        lockoutUntil.removeValue(forKey: childId)
    }

    // MARK: - Select Child Flow

    /// Full child selection flow: check lockout, verify PIN, handle success/failure.
    ///
    /// On success, clears the lockout state for the child and returns `true`.
    /// On failure, records the failed attempt and throws an appropriate error.
    ///
    /// - Parameters:
    ///   - childId: The ID of the child to select.
    ///   - pin: The raw PIN entered by the user.
    ///   - children: The current list of children (from pairing data or getUpdates).
    /// - Returns: `true` if the child was successfully authenticated.
    /// - Throws: `Allow2ChildShieldError` on failure.
    @discardableResult
    public func selectChild(
        _ childId: UInt64,
        pin: String,
        children: [Allow2Child]
    ) throws -> Bool {
        // Find the child
        guard let child = children.first(where: { $0.id == childId }) else {
            throw Allow2ChildShieldError.childNotFound(childId)
        }

        // Check lockout
        let (locked, remaining) = isLockedOut(childId)
        if locked {
            throw Allow2ChildShieldError.lockedOut(remainingSeconds: remaining)
        }

        // If the child has no PIN configured, allow through (honour system)
        guard child.pinHash != nil, child.pinSalt != nil,
              !(child.pinHash ?? "").isEmpty, !(child.pinSalt ?? "").isEmpty else {
            clearLockout(childId)
            return true
        }

        // Verify PIN
        if verifyPin(pin, for: child) {
            clearLockout(childId)
            return true
        } else {
            let lockoutSeconds = recordFailedAttempt(childId)
            if lockoutSeconds > 0 {
                throw Allow2ChildShieldError.lockedOut(remainingSeconds: lockoutSeconds)
            }

            lock.lock()
            let attempts = failedAttempts[childId] ?? 0
            lock.unlock()
            throw Allow2ChildShieldError.incorrectPin(failedAttempts: attempts)
        }
    }

    // MARK: - Private

    /// Check lockout state (must be called with lock held).
    private func _isLockedOut(_ childId: UInt64) -> (locked: Bool, remainingSeconds: Int) {
        guard let expiry = lockoutUntil[childId] else {
            return (false, 0)
        }

        let remaining = expiry.timeIntervalSinceNow
        if remaining > 0 {
            return (true, Int(remaining.rounded(.up)))
        }

        // Lockout expired -- clear state
        failedAttempts.removeValue(forKey: childId)
        lockoutUntil.removeValue(forKey: childId)
        return (false, 0)
    }

    /// Constant-time comparison of two hex strings to prevent timing attacks.
    ///
    /// Both strings are converted to `[UInt8]` and compared byte-by-byte
    /// with a bitwise OR accumulator, ensuring the comparison always
    /// takes the same time regardless of where a mismatch occurs.
    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let bytesA = Array(a.utf8)
        let bytesB = Array(b.utf8)

        guard bytesA.count == bytesB.count else {
            return false
        }

        var result: UInt8 = 0
        for i in 0..<bytesA.count {
            result |= bytesA[i] ^ bytesB[i]
        }

        return result == 0
    }
}
