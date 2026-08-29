import Foundation

/// How close a usage window is to its limit.
///
/// Purely a measurement: it says nothing about whether the reading could be obtained, only
/// what it says. Whether a provider answered at all is `UsageStatus`, and where the answer
/// came from is `UsageSource`. Keeping the three apart is what lets the UI show "90% used,
/// from cache" without either fact having to masquerade as the other.
public enum UsageLevel: String, Codable, Sendable, CaseIterable {
    case normal
    case warning
    case critical
    case exhausted

    /// Ordering for "worst wins" comparisons and for detecting escalation between reads.
    public var severity: Int {
        switch self {
        case .normal: 0
        case .warning: 1
        case .critical: 2
        case .exhausted: 3
        }
    }
}
