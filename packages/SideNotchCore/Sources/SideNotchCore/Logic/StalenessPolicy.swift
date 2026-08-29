import Foundation

/// Decides when a snapshot is too old to present as live.
///
/// Per `docs/DOMAIN_MODEL.md`: a stale snapshot is visually marked as stale; it is never
/// presented as live.
public struct StalenessPolicy: Sendable {
    /// Readings older than this are stale.
    public let maxAge: TimeInterval

    public static let `default` = StalenessPolicy(maxAge: 15 * 60)

    public init(maxAge: TimeInterval) {
        self.maxAge = maxAge
    }

    public func isStale(_ snapshot: UsageSnapshot, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.observedAt) > maxAge
    }
}
