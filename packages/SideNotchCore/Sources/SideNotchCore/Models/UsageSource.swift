import Foundation

/// How a snapshot was obtained. Surfaced in the UI so a reading's provenance is never implicit.
public enum UsageSource: String, Codable, Sendable {
    /// A documented provider API.
    case api
    /// Files the provider's own local app writes (session transcripts, local databases).
    case localApp
    /// Output of a provider's command-line tool.
    case cli
    /// An authenticated web session. Not used in V1 — see SECURITY.md.
    case webSession
    /// Entered by the user.
    case manual
    /// Fixture data for design and tests.
    case mock
}
