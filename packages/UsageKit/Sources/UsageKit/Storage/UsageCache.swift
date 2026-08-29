import Foundation
import SideNotchCore
import ProviderKit

/// Persists the last good reading per provider.
public protocol UsageCaching: Sendable {
    /// Every stored reading, marked `.cached`.
    func load() -> [ProviderType: UsageState]
    /// Stores a reading. Only `.available` states are worth keeping.
    func save(_ state: UsageState)
    func remove(_ provider: ProviderType)
}

/// A cache file on disk.
///
/// Deliberately a plain JSON document rather than SwiftData. The store holds one small
/// record per provider with no relationships and no queries, so a database engine bought
/// nothing — and cost something real: renaming the `@Model` entity during the Phase 1
/// refactor made CoreData truncate its history and silently drop every cached row. In a
/// released app that is user-visible data loss on an ordinary refactor.
///
/// A versioned document makes the same situation explicit: an unreadable or
/// wrong-version file is discarded on purpose, and the next refresh repopulates it. The
/// cache is an optimisation, never a source of truth, so losing it is always survivable.
public final class FileUsageCache: UsageCaching, @unchecked Sendable {
    /// Bump when the stored shape changes incompatibly. Older files are discarded rather
    /// than migrated: re-reading a provider costs a second, and a migration path that is
    /// never exercised is a liability.
    static let currentVersion = 1

    private struct Document: Codable {
        var version: Int
        var entries: [String: UsageState]
    }

    private let url: URL
    private let lock = NSLock()
    /// Written through on save so a load never has to hit the disk twice.
    private var entries: [String: UsageState]

    /// - Parameter directory: defaults to Application Support.
    public init(directory: URL? = nil, fileName: String = "usage-cache.json") {
        let base = directory ?? FileUsageCache.defaultDirectory
        url = base.appendingPathComponent(fileName)
        entries = FileUsageCache.read(from: url)
    }

    public static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("SideNotch", isDirectory: true)
    }

    public func load() -> [ProviderType: UsageState] {
        lock.lock(); defer { lock.unlock() }
        var result: [ProviderType: UsageState] = [:]
        for (key, state) in entries {
            // Marked on the way out, so a restored reading never presents as live.
            result[ProviderType(key)] = state.asCached()
        }
        return result
    }

    public func save(_ state: UsageState) {
        // Only genuine readings are worth persisting. An unsupported or failed state
        // carries nothing to restore and would mask the next real attempt.
        guard state.status == .available else { return }
        lock.lock()
        entries[state.provider.rawValue] = state
        let snapshot = entries
        lock.unlock()
        write(snapshot)
    }

    public func remove(_ provider: ProviderType) {
        lock.lock()
        entries.removeValue(forKey: provider.rawValue)
        let snapshot = entries
        lock.unlock()
        write(snapshot)
    }

    // MARK: Disk

    private static func read(from url: URL) -> [String: UsageState] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else {
            Log.app.notice("usage cache unreadable; starting empty")
            return [:]
        }
        guard document.version == currentVersion else {
            Log.app.notice("usage cache version \(document.version) ignored")
            return [:]
        }
        return document.entries
    }

    /// Writes atomically, so an interrupted save cannot leave a half-written file that the
    /// next launch would discard.
    private func write(_ entries: [String: UsageState]) {
        let document = Document(version: Self.currentVersion, entries: entries)
        guard let data = try? JSONEncoder().encode(document) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // A cache that cannot be written is a lost optimisation, not a failure worth
            // surfacing: everything still works, just without a warm start.
            Log.app.notice("could not write usage cache")
        }
    }
}

/// A cache that keeps nothing beyond the process.
///
/// Used for fixture runs, so mock figures can never reach the real file, and in tests.
public final class InMemoryUsageCache: UsageCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ProviderType: UsageState] = [:]

    public init() {}

    public func load() -> [ProviderType: UsageState] {
        lock.withLock { entries.mapValues { $0.asCached() } }
    }

    public func save(_ state: UsageState) {
        guard state.status == .available else { return }
        lock.withLock { entries[state.provider] = state }
    }

    public func remove(_ provider: ProviderType) {
        _ = lock.withLock { entries.removeValue(forKey: provider) }
    }
}
