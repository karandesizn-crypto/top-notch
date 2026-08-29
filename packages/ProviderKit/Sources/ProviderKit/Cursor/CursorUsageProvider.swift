import Foundation
import SideNotchCore

/// Cursor adapter — not implemented, because there is nothing local to read.
///
/// Cursor's global state database
/// (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`) was queried
/// across both its tables for every `usage`, `quota`, `limit`, and `subscription` key and
/// returned no usage rows; the only matches were cached file contents whose *filenames*
/// contained those words. Cursor fetches these figures from its servers per session and
/// does not persist them.
///
/// The only known route is replaying Cursor's private endpoints with the user's session
/// cookie, which the project rules exclude. Unlike Claude, there is not even a stale local
/// cache to fall back on.
///
/// If Cursor ships a documented usage API or a CLI that prints quota, this becomes a
/// drop-in replacement behind `UsageProvider` and nothing above it changes.
public struct CursorUsageProvider: UsageProvider {
    public let id: ProviderID = .cursor
    public let displayName = "Cursor"

    public init() {}

    public func fetchSnapshot() async throws -> UsageSnapshot {
        throw ProviderError.unsupported(
            reason: "Not exposed outside Cursor"
        )
    }
}
