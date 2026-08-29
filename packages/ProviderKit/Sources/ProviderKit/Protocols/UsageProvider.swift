import Foundation
import SideNotchCore

/// The single boundary between the UI and however a provider's usage is obtained.
///
/// Per `docs/ARCHITECTURE.md`, the UI never knows whether a reading came from an API, a
/// local file, or a CLI — only what the normalized `UsageSnapshot` says.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }

    /// Returns every limit window this provider currently exposes.
    ///
    /// Implementations must not throw for "no data available" — that is a legitimate
    /// result and should be returned as a snapshot with `health: .unavailable`. Throwing
    /// is reserved for genuine read failures.
    func fetchSnapshots() async throws -> [UsageSnapshot]
}
