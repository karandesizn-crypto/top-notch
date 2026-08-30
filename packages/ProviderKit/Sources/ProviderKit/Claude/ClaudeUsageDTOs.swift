import Foundation
import SideNotchCore

/// One limit window as the usage endpoint reports it.
///
/// `utilization` is a percentage (0–100), not a fraction, and the endpoint can exceed 100
/// on an overage plan. Normalization to a fraction happens in the mapper, and clamping in
/// `UsageWindow`, so this type stays a faithful record of what arrived.
struct ClaudeUsageWindowDTO: Sendable, Equatable {
    let utilization: Double
    let resetsAt: Date?

    /// Rejects values that cannot describe a real window.
    ///
    /// A negative or non-finite utilization means the response is not what we think it is;
    /// showing a ring for it would be showing a guess. The upper end is left open on
    /// purpose — over-100 is a legitimate overage reading, not corruption.
    var isValid: Bool {
        utilization.isFinite && utilization >= 0
    }
}

/// The parsed usage response, plus what was seen that we did not recognise.
///
/// The unknown-key list is the drift tripwire. This is an undocumented endpoint on a beta
/// header, so the schema can move without warning; recording the shape lets a later read
/// notice that it has, instead of silently mapping a renamed field to nothing and
/// presenting a confident zero.
struct ClaudeUsageResponse: Sendable {
    /// Recognised windows, keyed by their wire name.
    let windows: [String: ClaudeUsageWindowDTO]
    /// Top-level keys not in `knownWindowKeys`. Names only — these are schema, not data.
    let unknownKeys: [String]

    /// Window names this adapter understands, in the order the UI should prefer them.
    ///
    /// `five_hour` first because the rolling session window is the one that interrupts
    /// work; the weekly windows matter but rarely bite first.
    static let knownWindowKeys = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"]

    /// Human labels. Kept beside the keys so a new window ships as one edit.
    static let labels: [String: String] = [
        "five_hour": "Session",
        "seven_day": "Weekly",
        "seven_day_opus": "Weekly (Opus)",
        "seven_day_sonnet": "Weekly (Sonnet)",
    ]

    /// Nominal window lengths, used for the reset phrasing.
    static let durations: [String: TimeInterval] = [
        "five_hour": 18_000,
        "seven_day": 604_800,
        "seven_day_opus": 604_800,
        "seven_day_sonnet": 604_800,
    ]

    /// True when nothing recognisable came back.
    ///
    /// Distinguished from "all windows at zero", which is a legitimate reading for someone
    /// who has not used Claude this session.
    var isEmpty: Bool { windows.isEmpty }
}

/// Turns the endpoint's JSON into a validated `ClaudeUsageResponse`.
///
/// Separate from the provider so the whole schema contract can be tested against recorded
/// payloads with no network and no credential.
enum ClaudeUsageDecoder {

    /// Decodes and validates.
    ///
    /// Throws `invalidResponse` when the payload is not an object or contains no window we
    /// recognise — the two shapes that mean the interface has changed under us. A window
    /// that is present but malformed is dropped rather than fatal, so one bad field does
    /// not cost the user the readings that did arrive.
    static func decode(_ data: Data) throws -> ClaudeUsageResponse {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderError.invalidResponse(detail: "Usage response is not a JSON object")
        }

        var windows: [String: ClaudeUsageWindowDTO] = [:]
        var unknown: [String] = []

        for (key, value) in root {
            guard ClaudeUsageResponse.knownWindowKeys.contains(key) else {
                unknown.append(key)
                continue
            }
            guard
                let object = value as? [String: Any],
                let utilization = numeric(object["utilization"])
            else { continue }

            let dto = ClaudeUsageWindowDTO(
                utilization: utilization,
                resetsAt: date(object["resets_at"])
            )
            guard dto.isValid else { continue }
            windows[key] = dto
        }

        guard !windows.isEmpty else {
            // Naming the keys we did see is what makes a drift report actionable. They are
            // field names, never values.
            let seen = root.keys.sorted().prefix(8).joined(separator: ", ")
            throw ProviderError.invalidResponse(
                detail: "No recognised usage window. Keys seen: [\(seen)]"
            )
        }

        return ClaudeUsageResponse(windows: windows, unknownKeys: unknown.sorted())
    }

    /// Accepts the number whether it arrives as a JSON number or a string.
    ///
    /// Undocumented endpoints are not consistent about this, and a percentage that arrives
    /// quoted should not read as a missing window.
    static func numeric(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    /// Parses a reset timestamp in any of the forms this endpoint has been seen to use.
    ///
    /// ISO 8601 with and without fractional seconds, plus epoch seconds. Returning nil is
    /// safe: `UsageWindow` treats a missing reset date as "no countdown known" and the UI
    /// simply omits the phrase.
    static func date(_ value: Any?) -> Date? {
        if let seconds = value as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = value as? Int { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
        guard let string = value as? String, !string.isEmpty else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = withFraction.date(from: string) { return parsed }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let parsed = plain.date(from: string) { return parsed }

        return Double(string).map { Date(timeIntervalSince1970: $0) }
    }
}
