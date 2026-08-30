import Testing
import Foundation
import SideNotchCore
@testable import UsageKit

@Suite("Usage cache")
struct UsageCacheTests {

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usagecache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func reading(_ provider: ProviderType, percent: Double, at date: Date) -> UsageState {
        UsageState.live(
            provider: provider,
            windows: [UsageWindow.fromPercentage(id: "p", label: "30-day", percent: percent)],
            at: date
        )
    }

    @Test("a saved reading survives a new cache over the same file")
    func persistsAcrossInstances() {
        let directory = temporaryDirectory()
        let when = Date(timeIntervalSince1970: 1_700_000_000)

        let first = FileUsageCache(directory: directory)
        first.save(reading(.codex, percent: 42, at: when))

        // A second instance stands in for the next app launch. The clock is pinned just
        // after the reading, since this test is about persistence, not recency.
        let restored = FileUsageCache(directory: directory)
            .load(now: when.addingTimeInterval(60))
        let codex = try? #require(restored[.codex])
        #expect(codex?.usedPercentage.map { Int($0.rounded()) } == 42)
        #expect(codex?.lastUpdated == when)
    }

    @Test("restored readings are marked cached, never live")
    func restoredIsCached() throws {
        let directory = temporaryDirectory()
        FileUsageCache(directory: directory).save(reading(.codex, percent: 10, at: Date()))

        let restored = try #require(FileUsageCache(directory: directory).load()[.codex])
        // The whole point: a figure from a previous launch must not present as current.
        #expect(restored.source == .cached)
        #expect(restored.status == .available)
    }

    @Test("only readable states are persisted")
    func onlyAvailableIsPersisted() {
        let directory = temporaryDirectory()
        let cache = FileUsageCache(directory: directory)

        cache.save(UsageState.unsupported(provider: .claude, reason: "x"))
        cache.save(UsageState.unavailable(provider: .cursor, reason: "x"))
        cache.save(UsageState.failed(provider: .codex, reason: "x"))
        cache.save(UsageState.loading(provider: .codex))

        // None of these carry figures; persisting them would mask the next real attempt.
        #expect(FileUsageCache(directory: directory).load().isEmpty)
    }

    @Test("a newer reading replaces an older one for the same provider")
    func replacesByProvider() throws {
        let directory = temporaryDirectory()
        let cache = FileUsageCache(directory: directory)
        cache.save(reading(.codex, percent: 10, at: Date(timeIntervalSince1970: 1_000)))
        cache.save(reading(.codex, percent: 80, at: Date(timeIntervalSince1970: 2_000)))

        let restored = FileUsageCache(directory: directory)
            .load(now: Date(timeIntervalSince1970: 2_100))
        #expect(restored.count == 1)
        #expect(try #require(restored[.codex]).usedPercentage == 80)
    }

    @Test("a reading older than a day is not restored at all")
    func expiredReadingIsDropped() {
        // The cache is a warm start, not a history. A day-old percentage cannot describe
        // a five-hour window, and restoring it would rely on every downstream reader
        // noticing the timestamp — which is exactly the failure mode that made Claude's
        // own twelve-day-stale cache unusable.
        let directory = temporaryDirectory()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        FileUsageCache(directory: directory).save(reading(.codex, percent: 42, at: when))

        let justInside = when.addingTimeInterval(FileUsageCache.maximumAge - 60)
        let justOutside = when.addingTimeInterval(FileUsageCache.maximumAge + 60)

        #expect(FileUsageCache(directory: directory).load(now: justInside).count == 1)
        #expect(FileUsageCache(directory: directory).load(now: justOutside).isEmpty)
    }

    @Test("a reading with no timestamp is dropped rather than trusted")
    func undatedReadingIsDropped() {
        // We cannot show that it is recent, and the whole point of the bound is to avoid
        // displaying figures we cannot date.
        let undated = UsageState(
            provider: .codex,
            status: .available,
            source: .live,
            lastUpdated: nil,
            windows: [UsageWindow.fromPercentage(id: "p", label: "30-day", percent: 50)]
        )
        #expect(FileUsageCache.isExpired(undated, now: Date()))
    }

    @Test("providers are stored independently")
    func independentProviders() {
        let directory = temporaryDirectory()
        let cache = FileUsageCache(directory: directory)
        cache.save(reading(.codex, percent: 10, at: Date()))
        cache.save(reading(.claude, percent: 90, at: Date()))

        let restored = FileUsageCache(directory: directory).load()
        #expect(Set(restored.keys) == [.codex, .claude])
    }

    @Test("removing one provider leaves the others")
    func remove() {
        let directory = temporaryDirectory()
        let cache = FileUsageCache(directory: directory)
        cache.save(reading(.codex, percent: 10, at: Date()))
        cache.save(reading(.claude, percent: 90, at: Date()))
        cache.remove(.codex)

        #expect(Set(FileUsageCache(directory: directory).load().keys) == [.claude])
    }

    @Test("a corrupt file is discarded rather than crashing")
    func corruptFileIsSurvivable() {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("usage-cache.json")
        try? Data("this is not json".utf8).write(to: url)

        // A cache is an optimisation, never a source of truth — losing it must be
        // survivable, and the next refresh repopulates it.
        #expect(FileUsageCache(directory: directory).load().isEmpty)

        let cache = FileUsageCache(directory: directory)
        cache.save(reading(.codex, percent: 5, at: Date()))
        #expect(FileUsageCache(directory: directory).load().count == 1)
    }

    @Test("a file from a future version is ignored, not misread")
    func versionMismatchIsIgnored() {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("usage-cache.json")
        let future = #"{"version": 999, "entries": {}}"#
        try? Data(future.utf8).write(to: url)

        // This is the failure the SwiftData store hit during the Phase 1 rename: a shape
        // change silently dropped data. Now it is explicit and recoverable.
        #expect(FileUsageCache(directory: directory).load().isEmpty)
    }

    @Test("an unwritable directory degrades to a session-only cache")
    func unwritableDirectory() {
        // /dev/null cannot hold a directory, so every write fails.
        let cache = FileUsageCache(directory: URL(fileURLWithPath: "/dev/null/nope"))
        cache.save(reading(.codex, percent: 1, at: Date()))

        // The value stays usable for this session — a failed write costs the warm start,
        // not the reading — but nothing survives to the next launch.
        #expect(cache.load()[.codex]?.usedPercentage.map { Int($0.rounded()) } == 1)
        #expect(FileUsageCache(directory: URL(fileURLWithPath: "/dev/null/nope")).load().isEmpty)
    }

    @Test("the in-memory cache keeps nothing beyond itself")
    func inMemoryIsIsolated() {
        let cache = InMemoryUsageCache()
        cache.save(reading(.codex, percent: 33, at: Date()))
        #expect(cache.load()[.codex]?.usedPercentage.map { Int($0.rounded()) } == 33)
        #expect(cache.load()[.codex]?.source == .cached)
        // A second instance shares nothing, which is what keeps fixture runs from
        // contaminating real data.
        #expect(InMemoryUsageCache().load().isEmpty)
    }
}
