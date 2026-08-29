import Foundation
import SideNotchCore

/// Normalizes the Codex app-server reply into a `UsageState`.
///
/// Split out from the provider so it can be tested against recorded payloads without
/// launching a process.
enum CodexSnapshotMapper {

    static func snapshot(
        from response: GetAccountRateLimitsResponse,
        tokenUsage: GetAccountTokenUsageResponse? = nil,
        thresholds: UsageThresholds = .default,
        now: Date = Date()
    ) -> UsageState {
        // Prefer the metered bucket for `limitId` "codex"; the flat `rateLimits` field is
        // documented as a backward-compatible mirror and may not survive.
        let source = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits

        var windows: [UsageWindow] = []
        if let primary = source.primary {
            windows.append(window(from: primary, id: "primary", fallbackLabel: "Current window", thresholds: thresholds))
        }
        if let secondary = source.secondary {
            windows.append(window(from: secondary, id: "secondary", fallbackLabel: "Secondary window", thresholds: thresholds))
        }
        // A spend control is a real limit the user can hit, so it belongs beside the
        // metered windows rather than being dropped.
        if let spend = source.individualLimit {
            windows.append(
                UsageWindow(
                    id: "individualLimit",
                    label: "Spend limit",
                    usedFraction: UsageWindow.normalize(1 - spend.remainingPercent / 100),
                    resetDate: Date(timeIntervalSince1970: TimeInterval(spend.resetsAt)),
                    duration: nil,
                    level: UsageLevelEvaluator.level(
                        forUsedFraction: 1 - spend.remainingPercent / 100, thresholds: thresholds
                    )
                )
            )
        }

        var metadata: [String: String] = [:]
        if let limitId = source.limitId { metadata["limitId"] = limitId }
        if let limitName = source.limitName { metadata["limitName"] = limitName }
        if let reached = source.rateLimitReachedType { metadata["rateLimitReachedType"] = reached }
        if let spendReached = source.spendControlReached {
            metadata["spendControlReached"] = String(spendReached)
        }
        if let spend = source.individualLimit {
            metadata["spendUsed"] = spend.used
            metadata["spendLimit"] = spend.limit
        }
        if let tokenUsage {
            if let today = tokensToday(from: tokenUsage, now: now) {
                metadata["tokensToday"] = String(today)
            }
            if let lifetime = tokenUsage.summary?.lifetimeTokens {
                metadata["tokensLifetime"] = String(lifetime)
            }
        }

        // A reply with no windows at all is still a successful read — the account simply
        // has no metered limits — so this stays `.live`/`.available` rather than becoming
        // an error state.
        return UsageState.live(
            provider: .codex,
            plan: source.planType,
            windows: windows,
            credits: credits(from: source.credits, resetCredits: response.rateLimitResetCredits),
            metadata: metadata,
            at: now
        )
    }

    /// Tokens spent today, when the account has a bucket for today.
    ///
    /// Buckets are keyed by ISO day in the account's own reckoning; the comparison uses the
    /// local calendar, which is what the user means by "today". A missing bucket means no
    /// usage today, and returns nil rather than zero so the UI can omit the line entirely.
    static func tokensToday(from usage: GetAccountTokenUsageResponse, now: Date) -> Int64? {
        guard let buckets = usage.dailyUsageBuckets else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        return buckets.first { $0.startDate == today }?.tokens
    }

    private static func window(
        from dto: RateLimitWindowDTO,
        id: String,
        fallbackLabel: String,
        thresholds: UsageThresholds
    ) -> UsageWindow {
        let duration = dto.windowDurationMins.map { TimeInterval($0 * 60) }
        return UsageWindow.fromPercentage(
            id: id,
            label: ResetCalculator.windowLabel(forDuration: duration) ?? fallbackLabel,
            percent: dto.usedPercent,
            resetDate: dto.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            duration: duration,
            thresholds: thresholds
        )
    }

    private static func credits(
        from dto: CreditsSnapshotDTO?,
        resetCredits: RateLimitResetCreditsSummaryDTO?
    ) -> CreditsInfo? {
        guard dto != nil || resetCredits != nil else { return nil }
        return CreditsInfo(
            hasCredits: dto?.hasCredits ?? false,
            unlimited: dto?.unlimited ?? false,
            balance: dto?.balance,
            resetCreditsAvailable: resetCredits?.availableCount
        )
    }
}
