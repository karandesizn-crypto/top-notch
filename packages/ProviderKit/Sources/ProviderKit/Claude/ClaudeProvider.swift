import Foundation
import SideNotchCore

/// Reads Claude Code's own locally cached usage figures.
///
/// Claude Code writes `cachedUsageUtilization` into `~/.claude.json` whenever it refreshes
/// usage from the server. That block carries a normalized `limits` array — session and
/// weekly percentages with reset timestamps — which maps almost directly onto
/// `UsageSnapshot`.
///
/// Two consequences worth knowing:
///
/// 1. The cache refreshes only when Claude Code itself fetches. `fetchedAtMs` is therefore
///    the honest `observedAt`, and readings can be hours or days old. `StalenessPolicy`
///    decides what the UI does about that; this adapter never back-dates or freshens.
/// 2. `~/.claude.json` also holds account and OAuth material. This adapter decodes exactly
///    one key and nothing else, and never logs the raw file. See SECURITY.md.
public struct ClaudeProvider: UsageProvider {
    public let id: ProviderID = .claude

    private let configURL: URL

    public init(configURL: URL? = nil) {
        self.configURL = configURL
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
    }

    public func fetchSnapshots() async throws -> [UsageSnapshot] {
        guard FileManager.default.isReadableFile(atPath: configURL.path) else {
            return [unavailable("Claude Code config not found at ~/.claude.json")]
        }

        let data = try Data(contentsOf: configURL, options: .mappedIfSafe)
        let cache: CachedUsageUtilization?
        do {
            cache = try JSONDecoder().decode(ClaudeConfigSlice.self, from: data).cachedUsageUtilization
        } catch {
            return [unavailable("Could not read Claude's cached usage block")]
        }

        guard let cache, let limits = cache.utilization?.limits, !limits.isEmpty else {
            return [unavailable("Claude Code has not cached usage yet — open Claude Code to refresh")]
        }

        let observedAt = Date(timeIntervalSince1970: cache.fetchedAtMs / 1000)
        return limits.compactMap { snapshot(from: $0, observedAt: observedAt) }
    }

    private func snapshot(from limit: CachedLimit, observedAt: Date) -> UsageSnapshot? {
        guard let percent = limit.percent else { return nil }
        return UsageSnapshot(
            provider: .claude,
            percentageUsed: percent,
            remainingEstimate: max(0, 100 - percent),
            resetAt: limit.resetsAt.flatMap(Self.parseTimestamp),
            scope: Self.scope(for: limit),
            health: HealthEvaluator.health(forPercentageUsed: percent),
            observedAt: observedAt,
            source: .localApp,
            windowLabel: Self.label(for: limit),
            detail: limit.isActive == false ? "Window not currently active" : nil
        )
    }

    private func unavailable(_ reason: String) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude, scope: .session, health: .unavailable,
            observedAt: Date(), source: .localApp, detail: reason
        )
    }

    /// Maps Claude's `kind`/`group` onto our scopes. Unknown kinds fall back to `.model`
    /// rather than being dropped, so a new limit type still surfaces instead of vanishing.
    static func scope(for limit: CachedLimit) -> UsageScope {
        switch limit.group ?? limit.kind {
        case "session": .session
        case "weekly": .weekly
        case "monthly": .monthly
        default: limit.kind == "session" ? .session : .model
        }
    }

    static func label(for limit: CachedLimit) -> String {
        switch limit.kind {
        case "session": "5-hour session"
        case "weekly_all": "Weekly (all models)"
        case "weekly_opus": "Weekly (Opus)"
        case "weekly_sonnet": "Weekly (Sonnet)"
        case let other?: other.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: "Usage"
        }
    }

    /// Claude emits fractional-second ISO 8601 with an offset; `.withInternetDateTime`
    /// alone rejects those, so try both configurations.
    static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

// MARK: - Decoding

/// Deliberately narrow: decoding only this key means the rest of `~/.claude.json`
/// (OAuth account, project history) never enters memory as parsed values.
private struct ClaudeConfigSlice: Decodable {
    let cachedUsageUtilization: CachedUsageUtilization?
}

private struct CachedUsageUtilization: Decodable {
    let fetchedAtMs: Double
    let utilization: Utilization?
}

private struct Utilization: Decodable {
    let limits: [CachedLimit]?
}

struct CachedLimit: Decodable {
    let kind: String?
    let group: String?
    let percent: Double?
    let severity: String?
    let resetsAt: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, severity
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }
}
