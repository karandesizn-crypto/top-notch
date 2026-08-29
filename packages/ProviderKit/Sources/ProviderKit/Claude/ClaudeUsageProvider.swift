import Foundation
import SideNotchCore

/// Claude adapter — deliberately not implemented yet.
///
/// Three local sources were surveyed (see `docs/DATA_SOURCES.md`); none is currently
/// acceptable:
///
/// 1. **`~/.claude.json` → `cachedUsageUtilization`.** Carries exactly the right shape —
///    a `limits[]` array with `percent`, `resets_at`, and `is_active` per window — but it
///    refreshes only when Claude Code itself fetches. Readings observed on a real machine
///    were eleven days old. Presenting that as live would be worse than showing nothing.
/// 2. **Session transcript `quotaLimits`.** Emitted once, at the moment a limit is hit,
///    with no percentage. A rejection event, not a feed.
/// 3. **`api.anthropic.com/api/oauth/usage` with the stored OAuth token.** Returns live
///    figures, and is what comparable tools use. It is an undocumented private endpoint,
///    which the project rules exclude without explicit approval. It also carries a real
///    hazard: Anthropic rotates the refresh token on every refresh and revokes the whole
///    token family if an old one is reused, so a second refresher racing Claude Code can
///    invalidate the user's CLI login.
///
/// The wanted equivalent of Codex's app-server is a supported local interface. Until one
/// exists, or option 3 is explicitly approved, this reports `.unsupported` rather than
/// showing a stale number as if it were current.
public struct ClaudeUsageProvider: UsageProvider {
    public let providerType: ProviderType = .claude
    public let displayName = "Claude"

    public init() {}

    /// Reports unsupported rather than throwing: having no readable interface is a fact
    /// about the provider, not a failure of this attempt, and the UI needs to say so.
    public func fetchUsage() async throws -> UsageState {
        UsageState.unsupported(provider: providerType, reason: "No local usage API yet")
    }
}
