import Foundation

/// Decides when a cached snapshot is too old to present as live.
///
/// A stale snapshot is marked, never shown as if it were current. This matters more than
/// it sounds: a provider's cached figure can be hours old, and a confident-looking ring
/// over a stale number is worse than an honest "unavailable".
public struct StalenessPolicy: Sendable {
    public let maxAge: TimeInterval

    public static let `default` = StalenessPolicy(maxAge: 15 * 60)

    public init(maxAge: TimeInterval) {
        self.maxAge = maxAge
    }

    public func isStale(_ state: UsageState, now: Date = Date()) -> Bool {
        guard let age = age(of: state, now: now) else { return false }
        return age > maxAge
    }

    /// Nil when the state carries no figures, so "never read" is not mistaken for "fresh".
    public func age(of state: UsageState, now: Date = Date()) -> TimeInterval? {
        guard let lastUpdated = state.lastUpdated else { return nil }
        return now.timeIntervalSince(lastUpdated)
    }
}
