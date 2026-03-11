import Foundation

/// Standard Allow2 activity types as defined by the platform.
///
/// Screen Time (8) is the master quota. Gaming (3), Internet (1), Social (6)
/// are independent sub-quotas that stack under it.
public enum Allow2Activity: UInt64, Codable, Sendable, CaseIterable {
    case internet    = 1
    case computer    = 2
    case gaming      = 3
    case messaging   = 4
    case junkFood    = 5
    case lollies     = 6
    case electricity = 7
    case screenTime  = 8
    case social      = 9
    case phoneTime   = 10

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .internet:    return "Internet"
        case .computer:    return "Computer"
        case .gaming:      return "Gaming"
        case .messaging:   return "Messaging"
        case .junkFood:    return "Junk Food"
        case .lollies:     return "Lollies"
        case .electricity: return "Electricity"
        case .screenTime:  return "Screen Time"
        case .social:      return "Social Media"
        case .phoneTime:   return "Phone Time"
        }
    }
}

/// A request to check a specific activity, sent to the check API.
public struct ActivityCheck: Codable, Sendable {
    public let id: UInt64
    public let log: Bool

    public init(id: UInt64, log: Bool = true) {
        self.id = id
        self.log = log
    }

    /// Convenience initialiser from the Activity enum.
    public init(activity: Allow2Activity, log: Bool = true) {
        self.id = activity.rawValue
        self.log = log
    }
}
