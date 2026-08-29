import Foundation

// Wire types for the Codex app-server `account/rateLimits/read` response.
//
// Transcribed from the schema the installed binary emits via
// `codex app-server generate-json-schema` (codex-cli 0.147.0-alpha.1.2), not from
// observation of one account's reply. Every field the schema marks optional is optional
// here, including both windows — an account can legitimately have a primary window and no
// secondary one.
//
// Note these are camelCase, unlike the snake_case in Codex's session rollout logs.

struct GetAccountRateLimitsResponse: Decodable {
    /// Backward-compatible single-bucket view.
    let rateLimits: RateLimitSnapshotDTO
    /// Multi-bucket view keyed by metered limit id, e.g. "codex".
    let rateLimitsByLimitId: [String: RateLimitSnapshotDTO]?
    let rateLimitResetCredits: RateLimitResetCreditsSummaryDTO?
}

struct RateLimitSnapshotDTO: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindowDTO?
    let secondary: RateLimitWindowDTO?
    let credits: CreditsSnapshotDTO?
    let individualLimit: SpendControlLimitSnapshotDTO?
    let planType: String?
    let rateLimitReachedType: String?
    let spendControlReached: Bool?
}

struct RateLimitWindowDTO: Decodable {
    /// Integer percentage in the wire format. Decoded as Double so a future
    /// fractional value does not fail the whole response.
    let usedPercent: Double
    /// Unix seconds.
    let resetsAt: Int64?
    let windowDurationMins: Int64?
}

struct CreditsSnapshotDTO: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    /// Provider-formatted; passed through rather than parsed.
    let balance: String?
}

struct SpendControlLimitSnapshotDTO: Decodable {
    let limit: String
    let used: String
    let remainingPercent: Double
    let resetsAt: Int64
}

struct RateLimitResetCreditsSummaryDTO: Decodable {
    let availableCount: Int
    /// Detail rows may be capped by the backend, so this can be shorter than
    /// `availableCount`; nil means details were not fetched at all.
    let credits: [RateLimitResetCreditDTO]?
}

struct RateLimitResetCreditDTO: Decodable {
    let id: String
    let resetType: String
    let status: String
    let grantedAt: Int64
    let expiresAt: Int64?
    let title: String?
    let description: String?
}
