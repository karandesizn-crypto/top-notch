import Foundation
import SideNotchCore

/// One model bucket from Cursor's usage endpoint.
///
/// `maxRequestUsage` is nullable, and that null is meaningful: it marks a bucket with no
/// ceiling. A null must never be substituted with a plausible-looking denominator — an
/// unmetered bucket has no percentage, and inventing one would be exactly the fabrication
/// the project rules forbid.
struct CursorModelUsageDTO: Sendable, Equatable {
    let numRequests: Int
    let maxRequestUsage: Int?

    /// Nil when the bucket is unmetered. Callers render that as a count without a ring.
    var usedFraction: Double? {
        guard let maxRequestUsage, maxRequestUsage > 0 else { return nil }
        return Double(numRequests) / Double(maxRequestUsage)
    }

    var isValid: Bool {
        numRequests >= 0 && (maxRequestUsage.map { $0 >= 0 } ?? true)
    }
}

/// The parsed `/auth/usage` response.
struct CursorUsageResponse: Sendable {
    /// Model buckets, keyed by their wire name.
    let models: [String: CursorModelUsageDTO]
    /// Start of the current billing month, when stated. The quota resets a month after.
    let startOfMonth: Date?
    /// Top-level keys not recognised — the drift tripwire.
    let unknownKeys: [String]

    /// Buckets this adapter understands, in display order.
    ///
    /// `gpt-4` is Cursor's wire name for the premium-request pool, which is the one that
    /// actually runs out; `gpt-3.5-turbo` is the unmetered pool. The names are historical
    /// and no longer describe the models involved, which is precisely why they are pinned
    /// here rather than inferred.
    static let knownModelKeys = ["gpt-4", "gpt-3.5-turbo"]

    static let labels: [String: String] = [
        "gpt-4": "Premium requests",
        "gpt-3.5-turbo": "Basic requests",
    ]

    var isEmpty: Bool { models.isEmpty }
}

/// Decodes and validates Cursor's usage payload.
enum CursorUsageDecoder {

    static func decode(_ data: Data) throws -> CursorUsageResponse {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderError.invalidResponse(detail: "Usage response is not a JSON object")
        }

        var models: [String: CursorModelUsageDTO] = [:]
        var unknown: [String] = []
        var startOfMonth: Date?

        for (key, value) in root {
            if key == "startOfMonth" {
                startOfMonth = parseDate(value)
                continue
            }
            guard CursorUsageResponse.knownModelKeys.contains(key) else {
                unknown.append(key)
                continue
            }
            guard let object = value as? [String: Any] else { continue }

            let dto = CursorModelUsageDTO(
                numRequests: integer(object["numRequests"]) ?? 0,
                maxRequestUsage: integer(object["maxRequestUsage"])
            )
            guard dto.isValid else { continue }
            models[key] = dto
        }

        guard !models.isEmpty else {
            let seen = root.keys.sorted().prefix(8).joined(separator: ", ")
            throw ProviderError.invalidResponse(
                detail: "No recognised usage bucket. Keys seen: [\(seen)]"
            )
        }

        return CursorUsageResponse(
            models: models,
            startOfMonth: startOfMonth,
            unknownKeys: unknown.sorted()
        )
    }

    static func integer(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func parseDate(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        guard let string = value as? String, !string.isEmpty else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: string) { return parsed }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let parsed = plain.date(from: string) { return parsed }

        // Cursor has also been seen sending epoch milliseconds as a string.
        return Double(string).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// Maps a validated response into a `UsageState`.
enum CursorUsageMapper {

    /// What a *successful* read found, recorded in `metadata["outcome"]`.
    ///
    /// Exists so "we read your account and it has no metered limit" is never confused with
    /// "we could not read your account". Both leave the rail with nothing to draw, and
    /// without this the only thing separating them is the wording of a string sized for a
    /// 185pt rail.
    enum Outcome: String {
        /// A ceiling was present and a percentage could be computed.
        case metered
        /// The read worked; the account has no metered pool. Not a failure.
        case noMeteredQuota
    }

    static func snapshot(
        from response: CursorUsageResponse,
        thresholds: UsageThresholds = .default,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageState {
        // Cursor states the start of the billing month, not the reset. The reset is a month
        // on from it — computed with Calendar rather than by adding 30 days, so it lands on
        // the right day in a 28- or 31-day month.
        let resetDate = response.startOfMonth.flatMap {
            calendar.date(byAdding: .month, value: 1, to: $0)
        }

        let windows = CursorUsageResponse.knownModelKeys.compactMap { key -> UsageWindow? in
            guard let dto = response.models[key] else { return nil }
            let fraction = dto.usedFraction
            return UsageWindow(
                id: key,
                label: CursorUsageResponse.labels[key] ?? key,
                usedFraction: fraction,
                resetDate: resetDate,
                duration: resetDate.flatMap { reset in
                    response.startOfMonth.map { reset.timeIntervalSince($0) }
                },
                level: UsageLevelEvaluator.level(forUsedFraction: fraction, thresholds: thresholds)
            )
        }

        var metadata: [String: String] = [:]
        if !response.unknownKeys.isEmpty {
            metadata["schemaUnknownKeys"] = response.unknownKeys.joined(separator: ",")
        }
        // Request counts are useful in the expanded card and are not sensitive.
        for (key, dto) in response.models {
            metadata["\(key).used"] = String(dto.numRequests)
            if let max = dto.maxRequestUsage {
                metadata["\(key).limit"] = String(max)
            }
        }

        // A read that succeeded but found nothing measurable is not the same as a live
        // reading, and must not present as one. This is the ordinary case for an account on
        // usage-based pricing: the endpoint answers 200 with every ceiling null, because
        // the request pool it describes no longer governs the account. Reporting
        // `.available` there would put a provider with no figures next to two that have
        // them, with nothing to explain the gap.
        guard windows.contains(where: { $0.usedFraction != nil }) else {
            // Deliberately built with the full initializer rather than the `unavailable`
            // factory, so this outcome is not merely *worded* differently from a failure
            // but is distinguishable in the state itself.
            //
            // The read succeeded. There is simply nothing metered on this account — the
            // ordinary case under usage-based pricing, where the endpoint answers 200 with
            // every ceiling null. That is a fact about the plan, not a fault in the
            // integration, and anything inspecting the state (diagnostics, notifications,
            // a future settings screen) must be able to tell the two apart without
            // string-matching user-facing copy.
            //
            // `status` stays `.unavailable` because there is no measurement to draw, which
            // is what the rail needs to know; `outcome` carries the reason it is absent.
            metadata["outcome"] = Outcome.noMeteredQuota.rawValue
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
        metadata["outcome"] = Outcome.metered.rawValue

        return UsageState.live(
            provider: .cursor,
            windows: windows,
            metadata: metadata,
            at: now
        )
    }
}
