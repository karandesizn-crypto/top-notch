import Testing
import Foundation
import SideNotchCore
@testable import ProviderKit

private func fixture(_ path: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(path)")
}

@Suite("Claude adapter")
struct ClaudeProviderTests {
    @Test("parses session and weekly limits from the cached utilization block")
    func parsesLimits() async throws {
        let snapshots = try await ClaudeProvider(configURL: fixture("claude-config.json"))
            .fetchSnapshots()

        #expect(snapshots.count == 2)

        let session = try #require(snapshots.first { $0.scope == .session })
        #expect(session.percentageUsed == 50)
        #expect(session.remainingEstimate == 50)
        #expect(session.health == .healthy)
        #expect(session.windowLabel == "5-hour session")
        #expect(session.source == .localApp)

        let weekly = try #require(snapshots.first { $0.scope == .weekly })
        #expect(weekly.percentageUsed == 13)
        #expect(weekly.windowLabel == "Weekly (all models)")
        #expect(weekly.detail == "Window not currently active")
    }

    @Test("observedAt comes from fetchedAtMs, not from read time")
    func observedAtIsCacheTime() async throws {
        let snapshots = try await ClaudeProvider(configURL: fixture("claude-config.json"))
            .fetchSnapshots()
        let expected = Date(timeIntervalSince1970: 1_786_963_498.319)
        #expect(abs(snapshots[0].observedAt.timeIntervalSince(expected)) < 0.01)
    }

    @Test("fractional-second reset timestamps parse")
    func parsesResetTimestamp() async throws {
        let snapshots = try await ClaudeProvider(configURL: fixture("claude-config.json"))
            .fetchSnapshots()
        let session = try #require(snapshots.first { $0.scope == .session })
        let resetAt = try #require(session.resetAt)
        #expect(abs(resetAt.timeIntervalSince1970 - 1_786_963_800.17) < 1)
    }

    @Test("missing cache yields unavailable, not a throw or a fabricated zero")
    func missingCache() async throws {
        let snapshots = try await ClaudeProvider(configURL: fixture("claude-config-nocache.json"))
            .fetchSnapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].health == .unavailable)
        #expect(snapshots[0].percentageUsed == nil)
    }

    @Test("missing file yields unavailable")
    func missingFile() async throws {
        let snapshots = try await ClaudeProvider(configURL: fixture("does-not-exist.json"))
            .fetchSnapshots()
        #expect(snapshots[0].health == .unavailable)
    }
}

@Suite("Codex adapter")
struct CodexProviderTests {
    @Test("reads the most recent rate_limits event, not the first")
    func readsLatestEvent() async throws {
        let snapshots = try await CodexProvider(sessionsRoot: fixture("codex-sessions"))
            .fetchSnapshots()

        let monthly = try #require(snapshots.first { $0.scope == .monthly })
        #expect(monthly.percentageUsed == 60)   // the later event, not the earlier 35
        #expect(monthly.windowLabel == "30-day")
        #expect(monthly.detail == "Plan: go")
    }

    @Test("secondary window becomes its own snapshot")
    func secondaryWindow() async throws {
        let snapshots = try await CodexProvider(sessionsRoot: fixture("codex-sessions"))
            .fetchSnapshots()
        #expect(snapshots.count == 2)
        let session = try #require(snapshots.first { $0.scope == .session })
        #expect(session.percentageUsed == 12.5)
        #expect(session.windowLabel == "5-hour")
    }

    @Test("missing sessions directory yields unavailable")
    func missingRoot() async throws {
        let snapshots = try await CodexProvider(sessionsRoot: fixture("no-such-dir"))
            .fetchSnapshots()
        #expect(snapshots[0].health == .unavailable)
    }

    @Test(
        "window minutes map to scopes",
        arguments: [(300, UsageScope.session), (1440, .weekly), (10080, .weekly), (43200, .monthly)]
    )
    func scopeMapping(minutes: Int, expected: UsageScope) {
        #expect(CodexProvider.scope(forWindowMinutes: minutes) == expected)
    }

    @Test(
        "window labels",
        arguments: [(300, "5-hour"), (1440, "1-day"), (43200, "30-day"), (90, "90-minute")]
    )
    func labels(minutes: Int, expected: String) {
        #expect(CodexProvider.label(forWindowMinutes: minutes) == expected)
    }
}

@Suite("Cursor adapter")
struct CursorProviderTests {
    @Test("reports unavailable explicitly rather than disappearing from the rail")
    func alwaysUnavailable() async throws {
        let snapshots = try await CursorProvider().fetchSnapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots[0].health == .unavailable)
        #expect(snapshots[0].percentageUsed == nil)
        #expect(snapshots[0].detail != nil)
    }
}

@Suite("Mock provider")
struct MockProviderTests {
    @Test("showcase covers every provider and a range of health states")
    func showcase() async throws {
        let providers = MockProvider.showcase()
        #expect(Set(providers.map(\.id)) == Set(ProviderID.allCases))

        var healths = Set<UsageHealth>()
        for provider in providers {
            for snapshot in try await provider.fetchSnapshots() { healths.insert(snapshot.health) }
        }
        #expect(healths.contains(.healthy))
        #expect(healths.contains(.critical))
        #expect(healths.contains(.unavailable))
    }
}
