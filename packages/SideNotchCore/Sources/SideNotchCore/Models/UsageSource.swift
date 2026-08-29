import Foundation

/// Where the figures on screen came from.
///
/// The UI must never have to infer this. A cached reading and a live one look identical
/// otherwise, and presenting a stale figure as current is the failure this exists to
/// prevent.
public enum UsageSource: String, Codable, Sendable, CaseIterable {
    /// Read from the provider during this app session.
    case live
    /// Restored from disk; no successful read has happened yet this session.
    case cached
    /// No figures at all — nothing was read and nothing was cached.
    case unavailable
}
