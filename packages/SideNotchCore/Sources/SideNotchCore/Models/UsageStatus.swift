import Foundation

/// Whether a provider could be read, and how that attempt ended.
///
/// Distinct from `UsageLevel`, which describes the reading itself. A provider can be
/// `.available` at any level; it can be `.unsupported` with no level at all.
public enum UsageStatus: String, Codable, Sendable, CaseIterable {
    /// A first read is in flight and nothing is known yet.
    case loading
    /// The provider answered with usable figures.
    case available
    /// The provider is present but could not answer right now — not signed in, not
    /// running, a transient failure. Worth retrying.
    case unavailable
    /// The provider has no interface SideNotch can legitimately read. Retrying will not
    /// help; this is a statement about the provider, not about this attempt.
    case unsupported
    /// The read failed in a way that is neither transient nor structural.
    case error

    /// Whether figures should be shown at all.
    public var hasMeasurement: Bool { self == .available }

    /// Whether retrying could plausibly change the outcome.
    public var isRetryable: Bool {
        switch self {
        case .loading, .available, .unavailable, .error: true
        case .unsupported: false
        }
    }
}
