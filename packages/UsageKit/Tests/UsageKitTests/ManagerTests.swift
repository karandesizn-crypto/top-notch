import Testing
import Foundation
import SideNotchCore
import ProviderKit
@testable import UsageKit

/// A provider whose answers the test controls, and which counts how often it was asked.
private final class ScriptedProvider: UsageProvider, @unchecked Sendable {
    let providerType: ProviderType
    let displayName: String
    private let lock = NSLock()
    private var answers: [Result<UsageState, ProviderError>]
    private(set) var callCount = 0
    private(set) var startedMonitoring = false
    private(set) var stoppedMonitoring = false

    init(_ providerType: ProviderType, answers: [Result<UsageState, ProviderError>]) {
        self.providerType = providerType
        self.displayName = providerType.defaultDisplayName
        self.answers = answers
    }

    func startMonitoring() async { lock.withLock { startedMonitoring = true } }
    func stopMonitoring() async { lock.withLock { stoppedMonitoring = true } }

    func fetchUsage() async throws -> UsageState {
        let answer: Result<UsageState, ProviderError> = lock.withLock {
            callCount += 1
            return answers.count > 1 ? answers.removeFirst() : (answers.first ?? .failure(.unknown(detail: "none")))
        }
        return try answer.get()
    }
}

@MainActor
@Suite("Usage manager")
struct UsageManagerTests {

    private func settings() -> AppSettings {
        // A throwaway defaults domain, so tests never touch the user's preferences.
        let suite = UserDefaults(suiteName: "UsageManagerTests-\(UUID().uuidString)")!
        return AppSettings(defaults: suite)
    }

    private func reading(_ provider: ProviderType, percent: Double) -> UsageState {
        UsageState.live(
            provider: provider,
            windows: [UsageWindow.fromPercentage(id: "p", label: "30-day", percent: percent)]
        )
    }

    private func manager(
        _ providers: [any UsageProvider], cache: any UsageCaching = InMemoryUsageCache()
    ) -> UsageManager {
        UsageManager(
            settings: settings(), cache: cache,
            notifications: NotificationService(),
            indicatorHold: .zero,   // the hold is a presentation concern, not a test one
            providerOverride: providers
        )
    }

    @Test("a live reading reaches the UI-facing status")
    func liveReachesStatus() async {
        let provider = ScriptedProvider(.codex, answers: [.success(reading(.codex, percent: 40))])
        let manager = manager([provider])

        await manager.refresh(.codex)

        let status = manager.status(for: .codex)
        #expect(status?.status == .available)
        #expect(status?.source == .live)
        #expect(status?.headlineWindow?.usedPercentage.map { Int($0.rounded()) } == 40)
        #expect(status?.state == .normal)
    }

    @Test("a transient failure keeps the last good figures, marked cached")
    func transientFailureKeepsFigures() async {
        let provider = ScriptedProvider(.codex, answers: [
            .success(reading(.codex, percent: 55)),
            .failure(.notRunning),
        ])
        let manager = manager([provider])

        await manager.refresh(.codex)
        await manager.refresh(.codex)
        let status = manager.status(for: .codex)
        // The figure the user was reading must not blank on a blip...
        #expect(status?.headlineWindow?.usedPercentage.map { Int($0.rounded()) } == 55)
        // ...but it must stop claiming to be current.
        #expect(status?.source == .cached)
    }

    @Test("a successful read that finds nothing clears the figures, rather than hiding behind the cache")
    func authoritativeEmptyReadClearsFigures() async {
        // Cursor reports this when an account has no metered pool: the request succeeded,
        // and the honest answer is that there is no percentage. It is retryable — the plan
        // could change — but it is *not* a blip, so re-serving the last cached percentage
        // would show a number the account no longer has.
        let emptyButSuccessful = UsageState(
            provider: .cursor,
            status: .unavailable,
            source: .unavailable,
            lastUpdated: Date(),
            failure: "No metered quota",
            metadata: ["readSucceeded": "true", "outcome": "noMeteredQuota"]
        )
        let provider = ScriptedProvider(.cursor, answers: [
            .success(reading(.cursor, percent: 62)),
            .success(emptyButSuccessful),
        ])
        let manager = manager([provider])

        await manager.refresh(.cursor)
        await manager.refresh(.cursor)

        let status = manager.status(for: .cursor)
        #expect(status?.headlineWindow == nil)
        #expect(status?.statusMessage == "No metered quota")
    }

    @Test("a structural failure clears the figures")
    func unsupportedClearsFigures() async {
        let provider = ScriptedProvider(.claude, answers: [
            .success(reading(.claude, percent: 70)),
            .success(UsageState.unsupported(provider: .claude, reason: "No local usage API yet")),
        ])
        let manager = manager([provider])

        await manager.refresh(.claude)
        await manager.refresh(.claude)

        let status = manager.status(for: .claude)
        // An unsupported provider will never produce a newer reading, so a cached figure
        // would sit there looking current forever.
        #expect(status?.status == .unsupported)
        #expect(status?.headlineWindow == nil)
        #expect(status?.statusMessage == "No local usage API yet")
    }

    @Test("provider errors become the right status")
    func errorMapping() async {
        for (error, expected) in [
            (ProviderError.notInstalled, UsageStatus.unavailable),
            (.authenticationRequired, .unavailable),
            (.invalidResponse(detail: "x"), .error),
            (.unsupported(reason: "x"), .unsupported),
        ] {
            let provider = ScriptedProvider(.codex, answers: [.failure(error)])
            let manager = manager([provider])
            await manager.refresh(.codex)
            #expect(manager.status(for: .codex)?.status == expected)
        }
    }

    @Test("a cached reading is present before any refresh runs")
    func warmStart() {
        let cache = InMemoryUsageCache()
        cache.save(reading(.codex, percent: 33))

        let manager = manager([ScriptedProvider(.codex, answers: [])], cache: cache)

        // The surface shows something on launch rather than an empty ring.
        let status = manager.status(for: .codex)
        #expect(status?.headlineWindow?.usedPercentage.map { Int($0.rounded()) } == 33)
        #expect(status?.source == .cached)
    }

    @Test("a live refresh replaces the cached reading and its source")
    func liveReplacesCached() async {
        let cache = InMemoryUsageCache()
        cache.save(reading(.codex, percent: 33))
        let provider = ScriptedProvider(.codex, answers: [.success(reading(.codex, percent: 77))])
        let manager = manager([provider], cache: cache)

        #expect(manager.status(for: .codex)?.source == .cached)
        await manager.refresh(.codex)
        #expect(manager.status(for: .codex)?.source == .live)
        #expect(manager.status(for: .codex)?.headlineWindow?.usedPercentage.map { Int($0.rounded()) } == 77)
    }

    @Test("concurrent refreshes of one provider collapse into a single read")
    func concurrentRefreshesCoalesce() async {
        let provider = ScriptedProvider(.codex, answers: [.success(reading(.codex, percent: 1))])
        let manager = manager([provider])

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { await manager.refresh(.codex) } }
        }

        // The in-flight guard is what keeps a burst of triggers from hammering a provider.
        #expect(provider.callCount == 1)
    }

    @Test("one provider failing does not stop the others")
    func failureIsIsolated() async {
        let codex = ScriptedProvider(.codex, answers: [.success(reading(.codex, percent: 20))])
        let claude = ScriptedProvider(.claude, answers: [.failure(.unknown(detail: "boom"))])
        let manager = manager([claude, codex])

        await manager.refreshAll()

        #expect(manager.status(for: .codex)?.status == .available)
        #expect(manager.status(for: .claude)?.status == .error)
    }

    @Test("monitoring starts and stops with the manager")
    func monitoringLifecycle() async {
        let provider = ScriptedProvider(.codex, answers: [.success(reading(.codex, percent: 5))])
        let manager = manager([provider])

        await manager.start()
        #expect(provider.startedMonitoring)

        await manager.stop()
        #expect(provider.stoppedMonitoring)
    }

    @Test("a state with no figures is never called stale")
    func staleOnlyAppliesToFigures() async {
        let provider = ScriptedProvider(.claude, answers: [
            .success(UsageState.unsupported(provider: .claude, reason: "x"))
        ])
        let manager = manager([provider])
        await manager.refresh(.claude)

        // Marking an unsupported provider "stale" would imply it had once been fresh.
        #expect(manager.isStale(.claude) == false)
    }
}
