import Foundation
import SideNotchCore

/// Normalizes a validated Claude usage response into a `UsageState`.
///
/// Split from the provider so the mapping can be tested against recorded payloads without
/// a network call or a credential.
enum ClaudeUsageMapper {

    static func snapshot(
        from response: ClaudeUsageResponse,
        plan: String?,
        credentialOrigin: ClaudeOAuthCredential.Origin = .injected,
        thresholds: UsageThresholds = .default,
        now: Date = Date()
    ) -> UsageState {
        // Preferred order, not dictionary order, so the rail's window list is stable
        // between refreshes. An unstable order would make the expanded card reshuffle
        // under the pointer.
        let windows = ClaudeUsageResponse.knownWindowKeys.compactMap { key -> UsageWindow? in
            guard let dto = response.windows[key] else { return nil }
            return UsageWindow.fromPercentage(
                id: key,
                label: ClaudeUsageResponse.labels[key] ?? key,
                percent: dto.utilization,
                resetDate: dto.resetsAt,
                duration: ClaudeUsageResponse.durations[key],
                thresholds: thresholds
            )
        }

        var metadata: [String: String] = [:]
        // Recorded so a drift shows up in diagnostics before it shows up as a wrong
        // number. Key names only; the endpoint's values never land here.
        if !response.unknownKeys.isEmpty {
            metadata["schemaUnknownKeys"] = response.unknownKeys.joined(separator: ",")
        }
        metadata["windowsSeen"] = String(windows.count)
        // Which store answered. Names a location, never a value — and it is the first
        // thing worth knowing when the two stores disagree.
        metadata["credentialSource"] = credentialOrigin.rawValue

        return UsageState.live(
            provider: .claude,
            plan: plan,
            windows: windows,
            metadata: metadata,
            at: now
        )
    }
}
