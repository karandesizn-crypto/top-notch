import Foundation

/// Semantic state of a usage window.
///
/// `loading` and `unavailable` are distinct on purpose: "we have not asked yet" and "we
/// asked and the provider cannot tell us" look identical in a ring but mean different
/// things to the user, and only one of them is worth acting on.
public enum UsageState: String, Codable, Sendable, CaseIterable {
    case normal
    case warning
    case critical
    case exhausted
    case unavailable
    case loading

    /// Whether this state represents a real measurement.
    public var hasMeasurement: Bool {
        switch self {
        case .normal, .warning, .critical, .exhausted: true
        case .unavailable, .loading: false
        }
    }
}
