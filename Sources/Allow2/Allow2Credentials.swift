import Foundation
#if canImport(Security)
import Security
#endif

/// Stored pairing credentials for a paired device.
public struct Allow2PairedCredentials: Codable, Sendable {
    public let userId: UInt64
    public let pairId: UInt64
    public let pairToken: String
    public var children: [Allow2Child]

    public init(userId: UInt64, pairId: UInt64, pairToken: String, children: [Allow2Child] = []) {
        self.userId = userId
        self.pairId = pairId
        self.pairToken = pairToken
        self.children = children
    }
}

// MARK: - Protocol

/// Protocol for storing and retrieving device pairing credentials.
///
/// Implement this protocol to provide custom credential storage
/// (e.g., file-based for Linux, Keychain for Apple platforms).
public protocol Allow2CredentialStore: Sendable {
    /// Persist pairing credentials.
    func save(_ credentials: Allow2PairedCredentials) throws

    /// Load stored credentials. Returns `nil` if no credentials are stored.
    func load() -> Allow2PairedCredentials?

    /// Remove all stored credentials (unpair).
    func clear() throws
}

// MARK: - Keychain Implementation

#if canImport(Security)

/// Credential store backed by the Apple Keychain.
///
/// Uses a single Keychain item with a JSON-encoded blob.
/// Service name: `com.allow2.device-sdk`.
public final class KeychainCredentialStore: Allow2CredentialStore {

    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameters:
    ///   - service: Keychain service name. Default: `com.allow2.device-sdk`.
    ///   - account: Keychain account name. Default: `credentials`.
    public init(service: String = "com.allow2.device-sdk", account: String = "credentials") {
        self.service = service
        self.account = account
    }

    public func save(_ credentials: Allow2PairedCredentials) throws {
        let data = try encoder.encode(credentials)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Allow2Error.apiError(
                message: "Keychain save failed with status \(status)",
                code: Int(status)
            )
        }
    }

    public func load() -> Allow2PairedCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? decoder.decode(Allow2PairedCredentials.self, from: data)
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Allow2Error.apiError(
                message: "Keychain clear failed with status \(status)",
                code: Int(status)
            )
        }
    }
}

#endif
