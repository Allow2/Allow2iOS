# Allow2 Swift SDK v2

Allow2 Parental Freedom for apps and devices — Swift SDK for iOS, macOS, tvOS, and watchOS.

This is the **device-side SDK** for integrating Allow2 into apps, games, and devices owned by families. It handles pairing, child identification, permission checking, time warnings, offline operation, feedback, and "request more time" — everything a device needs to participate in the Allow2 ecosystem.

## Requirements

- iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+
- Swift 5.7+
- Xcode 14+

## Installation

### Swift Package Manager (recommended)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Allow2/allow2-swift.git", from: "2.0.0")
]
```

Or in Xcode: File > Add Package Dependencies > enter the repository URL.

Two library products are available:
- **`Allow2`** — Core SDK (no UI dependencies)
- **`Allow2UI`** — Optional SwiftUI views for block screens, child selector, warnings (coming soon)

## Quick Start

### 1. Register your app

Create a device/app at [https://developer.allow2.com](https://developer.allow2.com) to get your Device Token.

### 2. Initialise the SDK

```swift
import Allow2

let daemon = Allow2Daemon(
    deviceToken: "YOUR_DEVICE_TOKEN",
    environment: .production
)

// Set up event handlers
daemon.onBlocked = { isBlocked, reason in
    // Show/hide block screen
}

daemon.onWarning = { remainingSeconds in
    // Show countdown warning
}

daemon.onChildrenUpdated = { children in
    // Update child selector
}

// Start the SDK (loads credentials, begins check loop if paired)
await daemon.start()
```

### 3. Pair the device

Devices pair via QR code or PIN — the parent scans/enters the code on their Allow2 app. The device never handles parent credentials.

```swift
// Start a pairing session
let session = try await daemon.initPairing(
    deviceName: "My Game",
    method: .qrCode  // or .pinCode
)

// Display session.qrCodeData or session.pinCode to the user
// Then poll for completion:
let completed = try await daemon.checkPairingStatus(sessionId: session.sessionId)
```

### 4. Select a child

On shared devices, each child identifies themselves with their PIN:

```swift
let success = try daemon.selectChild(childId, pin: "1234")
```

PIN verification uses SHA-256 + salt hashing with progressive rate limiting (matching the server, Node SDK, and Brave browser implementations).

### 5. Check permissions

The SDK automatically checks permissions every 30 seconds once started. Results arrive via callbacks:

```swift
daemon.onCheckResult = { result in
    if !result.allowed {
        print("Blocked: \(result.activities)")
    }
}
```

Activities use stacking quotas — Screen Time (8) is the master, with Gaming (3), Internet (1), and Social (6) as independent sub-quotas. Blocked if ANY checked activity is blocked.

### 6. Request more time

Children can request additional time from their parent:

```swift
try await daemon.requestMoreTime(
    activityId: 3,  // Gaming
    minutes: 30,
    message: "Please! I'm almost finished this level"
)
```

### 7. Submit feedback

Parents can submit feedback about your product directly to you:

```swift
let discussionId = try await daemon.submitFeedback(
    category: .bug,
    message: "The app crashes when my child tries to open settings",
    deviceContext: .current(appVersion: "1.2.3")
)
```

You receive feedback in the [developer portal](https://developer.allow2.com) with threaded conversations and email notifications.

## Architecture

The SDK is composed of focused modules, all orchestrated by `Allow2Daemon`:

| Module | Purpose |
|--------|---------|
| `Allow2Api` | URLSession-based API client with environment switching |
| `Allow2Credentials` | Protocol-based credential storage (Keychain default) |
| `Allow2Pairing` | QR/PIN pairing sessions (no parent credentials on device) |
| `Allow2ChildShield` | PIN verification with SHA-256 + salt, progressive lockout |
| `Allow2Checker` | Periodic permission check loop (30s default) |
| `Allow2Warnings` | Progressive warnings (15m, 5m, 1m, 30s, 10s) — fire once per level |
| `Allow2Offline` | Cache last check, grace period, deny-by-default |
| `Allow2Request` | Request more time with status polling |
| `Allow2Feedback` | Submit feedback, view threads, reply |
| `Allow2Updates` | Poll for child/activity list changes |

### Credential Storage

By default, credentials are stored in the Keychain (`KeychainCredentialStore`). You can provide a custom implementation:

```swift
class MyCredentialStore: Allow2CredentialStore {
    func save(userId: UInt64, pairId: UInt64, pairToken: String) throws { ... }
    func load() -> (userId: UInt64, pairId: UInt64, pairToken: String)? { ... }
    func clear() throws { ... }
}

let daemon = Allow2Daemon(
    deviceToken: "...",
    credentialStore: MyCredentialStore()
)
```

### Offline Operation

When the device can't reach the API:
1. **Grace period** (default 5 minutes): cached check result is used
2. **After grace period**: deny-by-default (blocked)

This ensures children can't bypass controls by disabling Wi-Fi.

### Warning Progression

Warnings fire once per level transition to avoid spamming:

| Level | Remaining | Suggested Action |
|-------|-----------|-----------------|
| 15 min | 900s | Gentle notification |
| 5 min | 300s | Prominent warning |
| 1 min | 60s | Urgent warning |
| 30 sec | 30s | Countdown overlay |
| 10 sec | 10s | Final countdown |
| Blocked | 0s | Full block screen |

## Device Lifecycle

Every Allow2 integration follows this lifecycle:

1. **Pairing** (one-time) — QR code or 6-digit PIN, parent never enters credentials on device
2. **Child identification** (every session) — OS account mapping, child selector with PIN, or verification via the child's Allow2 app (iOS/Android) or web portal
3. **Parent access** — parent verifies via their Allow2 app or locally with PIN for unrestricted mode
4. **Permission checks** (continuous) — POST to service URL every 30-60s with `log: true`
5. **Warnings & countdowns** — progressive alerts before blocking
6. **Request more time** — child requests, parent approves/denies from their phone (also works offline)
7. **Feedback** — bug reports and feature requests sent directly to you, the developer

## Migration from v1

v2 is a complete rewrite. Key changes:
- **No username/password pairing** — QR/PIN only (parent credentials never on device)
- **SPM-only** — CocoaPods/Carthage/manual integration removed
- **Async/await** — modern Swift concurrency (iOS 15+)
- **Keychain credentials** — not UserDefaults
- **Protocol-oriented** — injectable dependencies, testable
- **Platform-agnostic core** — no UIKit in the SDK layer

The legacy v1 framework remains in `Allow2Framework/` for reference.

## Support

- Developer Portal: [https://developer.allow2.com](https://developer.allow2.com)
- Documentation: [https://developer.allow2.com/docs](https://developer.allow2.com/docs)
- Issues: [https://github.com/Allow2/allow2-swift/issues](https://github.com/Allow2/allow2-swift/issues)

## License

Copyright 2017-2026 Allow2 Pty Ltd. All rights reserved.
