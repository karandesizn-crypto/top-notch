import Foundation
import SideNotchCore

/// Cursor's current billing period, as the dashboard service reports it.
///
/// This is the reading that actually describes a modern Cursor account. The older
/// `/auth/usage` endpoint still answers, but on usage-based pricing every ceiling in it is
/// null — it describes a request pool that no longer governs the account — so it yields no
/// percentage at all. This one carries a real one.
struct CursorPeriodUsageDTO: Sendable, Equatable {
    /// 0–100 across the whole included allowance.
    let totalPercentUsed: Double
    /// Sub-metrics, kept for the expanded card. Neither is the headline.
    let apiPercentUsed: Double?
    let autoPercentUsed: Double?
    /// Included allowance and what is left of it, in cents.
    let limitCents: Int?
    let remainingCents: Int?
    let billingCycleStart: Date?
    let billingCycleEnd: Date?

    /// A percentage with no allowance behind it describes nothing, so it is not treated as
    /// a measurement. Same rule as the legacy path: no ceiling, no ring.
    var isMetered: Bool {
        guard let limitCents else { return false }
        return limitCents > 0
    }

    var isValid: Bool {
        totalPercentUsed.isFinite && totalPercentUsed >= 0
    }
}

/// Decodes and validates the Connect RPC usage payload.
enum CursorPeriodUsageDecoder {

    /// Top-level keys this adapter understands. Anything else is drift signal.
    ///
    /// The response carries a good deal we deliberately ignore — display copy, a 28-entry
    /// model list, threshold hints. Listing what we know keeps the unknown-key tripwire
    /// meaningful instead of permanently noisy.
    static let knownKeys: Set<String> = [
        "planUsage", "billingCycleStart", "billingCycleEnd", "spendLimitUsage",
        "enabled", "displayThreshold", "displayMessage", "autoBucketModels",
        "autoModelSelectedDisplayMessage", "namedModelSelectedDisplayMessage",
    ]

    static func decode(_ data: Data) throws -> CursorPeriodUsageDTO {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderError.invalidResponse(detail: "Usage response is not a JSON object")
        }
        guard let plan = root["planUsage"] as? [String: Any] else {
            let seen = root.keys.sorted().prefix(8).joined(separator: ", ")
            throw ProviderError.invalidResponse(
                detail: "No planUsage in response. Keys seen: [\(seen)]"
            )
        }
        guard let total = CursorUsageDecoder.number(plan["totalPercentUsed"]) else {
            let seen = plan.keys.sorted().prefix(8).joined(separator: ", ")
            throw ProviderError.invalidResponse(
                detail: "No totalPercentUsed. planUsage keys: [\(seen)]"
            )
        }

        let dto = CursorPeriodUsageDTO(
            totalPercentUsed: total,
            apiPercentUsed: CursorUsageDecoder.number(plan["apiPercentUsed"]),
            autoPercentUsed: CursorUsageDecoder.number(plan["autoPercentUsed"]),
            limitCents: CursorUsageDecoder.integer(plan["limit"]),
            remainingCents: CursorUsageDecoder.integer(plan["remaining"]),
            billingCycleStart: CursorUsageDecoder.parseDate(root["billingCycleStart"]),
            billingCycleEnd: CursorUsageDecoder.parseDate(root["billingCycleEnd"])
        )
        guard dto.isValid else {
            throw ProviderError.invalidResponse(detail: "Implausible totalPercentUsed")
        }
        return dto
    }

    /// Unrecognised top-level keys, for the drift log.
    static func unknownKeys(in data: Data) -> [String] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return root.keys.filter { !knownKeys.contains($0) }.sorted()
    }
}

/// Maps the billing-period reading into a `UsageState`.
enum CursorPeriodUsageMapper {

    static func snapshot(
        from dto: CursorPeriodUsageDTO,
        unknownKeys: [String] = [],
        thresholds: UsageThresholds = .default,
        now: Date = Date()
    ) -> UsageState {
        var metadata: [String: String] = [:]
        if !unknownKeys.isEmpty {
            metadata["schemaUnknownKeys"] = unknownKeys.joined(separator: ",")
        }
        if let limit = dto.limitCents { metadata["includedLimitCents"] = String(limit) }
        if let remaining = dto.remainingCents { metadata["remainingCents"] = String(remaining) }
        // Recorded raw rather than formatted: these are cents in a currency the response
        // never names, and guessing a symbol would be inventing information.
        if let api = dto.apiPercentUsed { metadata["apiPercentUsed"] = String(api) }
        if let auto = dto.autoPercentUsed { metadata["autoPercentUsed"] = String(auto) }
        metadata["source"] = "dashboard"

        guard dto.isMetered else {
            metadata["outcome"] = CursorUsageMapper.Outcome.noMeteredQuota.rawValue
            metadata["readSucceeded"] = "true"
            return UsageState(
                provider: .cursor,
                status: .unavailable,
                source: .unavailable,
                lastUpdated: now,
                failure: "No metered quota",
                metadata: metadata
            )
        }

        metadata["outcome"] = CursorUsageMapper.Outcome.metered.rawValue

        let duration = dto.billingCycleEnd.flatMap { end in
            dto.billingCycleStart.map { end.timeIntervalSince($0) }
        }
        let window = UsageWindow.fromPercentage(
            id: "billingPeriod",
            label: "Included usage",
            percent: dto.totalPercentUsed,
            resetDate: dto.billingCycleEnd,
            duration: duration,
            thresholds: thresholds
        )

        return UsageState.live(
            provider: .cursor,
            windows: [window],
            metadata: metadata,
            at: now
        )
    }
}
