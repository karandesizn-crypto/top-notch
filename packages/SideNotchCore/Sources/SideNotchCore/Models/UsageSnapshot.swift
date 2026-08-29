import Foundation

/// A single normalized usage reading for one provider and one limit window.
///
/// Per `docs/ARCHITECTURE.md`: never fabricate a value the provider does not expose.
/// `percentageUsed`, `remainingEstimate`, and `resetAt` are all optional for that reason —
/// a provider that reports token counts but no denominator yields a snapshot with a nil
/// percentage rather than a guessed one.
public struct UsageSnapshot: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let provider: ProviderID
    /// 0...100 when known.
    public let percentageUsed: Double?
    public let remainingEstimate: Double?
    public let resetAt: Date?
    public let scope: UsageScope
    public let health: UsageHealth
    public let observedAt: Date
    public let source: UsageSource
    /// Human-readable label for the window, e.g. "5-hour session" or "30-day".
    public let windowLabel: String?
    /// Why the reading is unavailable or degraded. Shown verbatim in the detail card.
    public let detail: String?

    public init(
        id: UUID = UUID(),
        provider: ProviderID,
        percentageUsed: Double? = nil,
        remainingEstimate: Double? = nil,
        resetAt: Date? = nil,
        scope: UsageScope,
        health: UsageHealth,
        observedAt: Date,
        source: UsageSource,
        windowLabel: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.percentageUsed = percentageUsed
        self.remainingEstimate = remainingEstimate
        self.resetAt = resetAt
        self.scope = scope
        self.health = health
        self.observedAt = observedAt
        self.source = source
        self.windowLabel = windowLabel
        self.detail = detail
    }
}
