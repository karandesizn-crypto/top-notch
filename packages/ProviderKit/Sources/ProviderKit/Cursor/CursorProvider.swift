import Foundation
import SideNotchCore

/// Cursor placeholder.
///
/// Cursor does not persist usage or quota data on disk. Its global state database
/// (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`) was queried for
/// every `usage`, `quota`, `limit`, and `subscription` key and returned nothing — the
/// figures shown in Cursor's own UI are fetched from its servers per session.
///
/// The only known way to obtain them is to replay Cursor's private endpoints with the
/// user's session cookie. Both `SECURITY.md` ("do not upload browser cookies/session
/// cookies") and the Phase 4 rule in `CLAUDE_CODE_BUILD_PLAN.md` ("never scrape or
/// reverse-engineer private endpoints as a default architecture") rule that out, so this
/// adapter reports honestly rather than guessing.
///
/// It stays in the rail as an explicit unavailable row: `DOMAIN_MODEL.md` requires that a
/// value the provider does not expose is never fabricated, and a visible "unavailable" is
/// more useful than a silently missing provider.
public struct CursorProvider: UsageProvider {
    public let id: ProviderID = .cursor

    public init() {}

    public func fetchSnapshots() async throws -> [UsageSnapshot] {
        [
            UsageSnapshot(
                provider: .cursor,
                scope: .session,
                health: .unavailable,
                observedAt: Date(),
                source: .localApp,
                windowLabel: "Not exposed locally",
                detail: "Cursor keeps usage server-side. Check cursor.com/dashboard."
            )
        ]
    }
}
