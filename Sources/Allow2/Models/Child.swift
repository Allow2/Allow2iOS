import Foundation

/// Represents a child entity within a controller's Allow2 account.
///
/// A child is NOT a user account -- it is a row in the controller's account.
/// The child may optionally have a linked user account (`linkedAccountId`).
public struct Allow2Child: Codable, Identifiable, Sendable {
    public let id: UInt64
    public let name: String
    public let pinHash: String?
    public let pinSalt: String?
    public let avatarUrl: String?
    public let linkedAccountId: UInt64?
    public let color: String?
    public let hasAccount: Bool

    public init(
        id: UInt64,
        name: String,
        pinHash: String? = nil,
        pinSalt: String? = nil,
        avatarUrl: String? = nil,
        linkedAccountId: UInt64? = nil,
        color: String? = nil,
        hasAccount: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pinHash = pinHash
        self.pinSalt = pinSalt
        self.avatarUrl = avatarUrl
        self.linkedAccountId = linkedAccountId
        self.color = color
        self.hasAccount = hasAccount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case pinHash = "pin_hash"
        case pinSalt = "pin_salt"
        case avatarUrl = "avatar_url"
        case linkedAccountId = "LinkedUserId"
        case color
        case hasAccount = "has_account"
    }
}
