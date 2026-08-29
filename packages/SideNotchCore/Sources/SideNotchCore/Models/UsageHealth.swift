import Foundation

/// Semantic state of a usage snapshot, derived from thresholds by `HealthEvaluator`.
public enum UsageHealth: String, Codable, Sendable {
    case healthy
    case warning
    case critical
    case exhausted
    /// The provider does not expose this data, or it could not be read.
    case unavailable
}
