import Foundation
import SideNotchCore

/// Reads Codex CLI rate limits from its own session rollout files.
///
/// Codex writes a `token_count` event on every turn containing a `rate_limits` block with
/// `used_percent`, `window_minutes`, and `resets_at`. That makes it the most complete local
/// source of the three providers: a real percentage, a real reset time, and no credentials
/// involved.
///
/// Rollouts live at `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`. The
/// newest file's last `rate_limits` event is the current state.
public struct CodexProvider: UsageProvider {
    public let id: ProviderID = .codex

    private let sessionsRoot: URL

    public init(sessionsRoot: URL? = nil) {
        self.sessionsRoot = sessionsRoot
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".codex/sessions")
    }

    public func fetchSnapshots() async throws -> [UsageSnapshot] {
        guard let newest = try newestRollout() else {
            return [unavailable("No Codex sessions found in ~/.codex/sessions")]
        }

        let found = try TailScanner.findFromEnd(at: newest.url) { line -> RateLimits? in
            guard line.contains("\"rate_limits\"") else { return nil }
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(RolloutLine.self, from: data)
            else { return nil }
            return event.payload?.rateLimits
        }

        guard let limits = found else {
            return [unavailable("Codex session has no rate limit data yet")]
        }

        let observedAt = newest.modified
        var snapshots = [UsageSnapshot]()
        if let primary = limits.primary {
            snapshots.append(snapshot(from: primary, observedAt: observedAt, planType: limits.planType))
        }
        if let secondary = limits.secondary {
            snapshots.append(snapshot(from: secondary, observedAt: observedAt, planType: limits.planType))
        }
        return snapshots.isEmpty ? [unavailable("Codex reported no active limit window")] : snapshots
    }

    private func snapshot(from window: RateWindow, observedAt: Date, planType: String?) -> UsageSnapshot {
        let percent = window.usedPercent
        return UsageSnapshot(
            provider: .codex,
            percentageUsed: percent,
            remainingEstimate: percent.map { max(0, 100 - $0) },
            resetAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) },
            scope: Self.scope(forWindowMinutes: window.windowMinutes),
            health: HealthEvaluator.health(forPercentageUsed: percent),
            observedAt: observedAt,
            source: .localApp,
            windowLabel: Self.label(forWindowMinutes: window.windowMinutes),
            detail: planType.map { "Plan: \($0)" }
        )
    }

    private func unavailable(_ reason: String) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex, scope: .session, health: .unavailable,
            observedAt: Date(), source: .localApp, detail: reason
        )
    }

    /// Newest rollout by file modification time. Codex nests by date, so a plain recursive
    /// enumeration is simpler and more robust than parsing the path.
    private func newestRollout() throws -> (url: URL, modified: Date)? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsRoot.path),
              let enumerator = fm.enumerator(
                at: sessionsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              )
        else { return nil }

        var newest: (URL, Date)?
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-"),
                  let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                      .contentModificationDate
            else { continue }
            if newest == nil || modified > newest!.1 { newest = (url, modified) }
        }
        return newest.map { (url: $0.0, modified: $0.1) }
    }

    static func scope(forWindowMinutes minutes: Int?) -> UsageScope {
        guard let minutes else { return .session }
        switch minutes {
        case ..<(60 * 24): return .session
        case ..<(60 * 24 * 10): return .weekly
        default: return .monthly
        }
    }

    static func label(forWindowMinutes minutes: Int?) -> String {
        guard let minutes else { return "Usage" }
        if minutes % (60 * 24) == 0 { return "\(minutes / (60 * 24))-day" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-minute"
    }
}

// MARK: - Decoding

private struct RolloutLine: Decodable {
    let payload: Payload?
}

private struct Payload: Decodable {
    let rateLimits: RateLimits?
    enum CodingKeys: String, CodingKey { case rateLimits = "rate_limits" }
}

private struct RateLimits: Decodable {
    let primary: RateWindow?
    let secondary: RateWindow?
    let planType: String?
    enum CodingKeys: String, CodingKey {
        case primary, secondary
        case planType = "plan_type"
    }
}

struct RateWindow: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Double?
    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}
