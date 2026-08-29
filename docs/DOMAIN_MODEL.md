# Domain Model

```swift
enum ProviderID: String, Codable, CaseIterable {
    case claude
    case cursor
    case codex
}

enum UsageHealth: String, Codable {
    case healthy
    case warning
    case critical
    case exhausted
    case unavailable
}

struct UsageSnapshot: Codable, Identifiable {
    let id: UUID
    let provider: ProviderID
    let percentageUsed: Double?
    let remainingEstimate: Double?
    let resetAt: Date?
    let scope: UsageScope
    let health: UsageHealth
    let observedAt: Date
    let source: UsageSource
}

enum UsageScope: String, Codable {
    case session
    case weekly
    case monthly
    case model
}

enum UsageSource: Codable {
    case api
    case localApp
    case cli
    case webSession
    case manual
    case mock
}
```

## Rules
- `percentageUsed` is 0...100 when known.
- `resetAt` is optional because not every provider exposes it.
- `health` is derived from configurable thresholds.
- A stale snapshot is visually marked as stale; it is never presented as live.
