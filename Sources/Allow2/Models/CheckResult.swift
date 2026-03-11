import Foundation

/// Result of a permission check from the Allow2 API.
public struct CheckResult: Codable, Sendable {

    /// Whether ALL requested activities are currently allowed.
    public let allowed: Bool

    /// Per-activity results.
    public let activities: [ActivityResult]

    /// Active day types for the current child.
    public let dayTypes: DayTypesInfo

    /// Children on this account (refreshed with each check).
    public let children: [Allow2Child]

    /// Subscription status.
    public let subscription: SubscriptionInfo

    /// When this check result expires (server UTC timestamp).
    public let expires: Date?

    private enum CodingKeys: String, CodingKey {
        case allowed
        case activities
        case dayTypes
        case children
        case subscription
        case expires
    }

    /// Memberwise initialiser (needed because custom CodingKeys suppress the default).
    public init(
        allowed: Bool,
        activities: [ActivityResult],
        dayTypes: DayTypesInfo,
        children: [Allow2Child],
        subscription: SubscriptionInfo,
        expires: Date? = nil
    ) {
        self.allowed = allowed
        self.activities = activities
        self.dayTypes = dayTypes
        self.children = children
        self.subscription = subscription
        self.expires = expires
    }
}

/// Per-activity result within a check response.
public struct ActivityResult: Codable, Sendable, Identifiable {

    /// Activity ID.
    public let id: UInt64

    /// Activity display name.
    public let name: String

    /// Whether this specific activity is currently allowed.
    public let allowed: Bool

    /// Whether this activity is permanently banned (not just time-limited).
    public let banned: Bool

    /// Remaining seconds for this activity. `nil` means unlimited.
    public let remaining: Int?

    /// Current time block info, if the activity is within a scheduled block.
    public let timeBlock: TimeBlockInfo?

    /// Active bans on this activity.
    public let bans: [BanInfo]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case allowed
        case banned
        case remaining
        case timeBlock
        case bans
    }
}

/// Information about a time block restriction.
public struct TimeBlockInfo: Codable, Sendable {
    /// Start of the blocked period (minutes from midnight).
    public let start: Int
    /// End of the blocked period (minutes from midnight).
    public let end: Int
}

/// Information about an active ban.
public struct BanInfo: Codable, Sendable {
    public let id: UInt64?
    public let reason: String?
    public let expires: Date?
}

/// Day type information returned in check results.
public struct DayTypesInfo: Codable, Sendable {
    public let today: [DayTypeEntry]
    public let tomorrow: [DayTypeEntry]?
}

/// A single day type entry (e.g. "School Day", "Weekend").
public struct DayTypeEntry: Codable, Sendable {
    public let id: UInt64
    public let name: String
}

/// Subscription status of the controller account.
public struct SubscriptionInfo: Codable, Sendable {
    public let active: Bool
    public let type: String?
    public let expires: Date?
}
