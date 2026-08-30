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

    /// Oldest reading worth restoring.
    ///
    /// The cache exists to avoid a blank rail in the second between launch and the first
    /// read — it is not a history. A figure from days ago cannot serve that purpose for any
    /// window this app tracks: the longest is seven days and the shortest is five hours, so
    /// a day-old percentage is somewhere between meaningless and misleading.
    ///
    /// This matters because the machine it was built on had exactly this failure in another
    /// form: a `cachedUsageUtilization` blob twelve days stale, which looked entirely
    /// current to anything that did not check its timestamp. Old entries are dropped on
    /// load, so a stale figure cannot come back at all rather than coming back and relying
    /// on every downstream reader to notice.
    public static let maximumAge: TimeInterval = 24 * 60 * 60

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
        // Renamed with the product. No fallback to the old location on purpose: this
        // file is a warm start, not data, and one refresh rebuilds it. The Logos directory
        // beside it holds files a person put there by hand and *does* keep a fallback.
        return support.appendingPathComponent("Top Notch", isDirectory: true)
    }

    public func load() -> [ProviderType: UsageState] {
        load(now: Date())
    }

    /// Clock-injectable form, so the expiry bound can be tested without waiting a day.
    func load(now: Date) -> [ProviderType: UsageState] {
        lock.lock(); defer { lock.unlock() }
        var result: [ProviderType: UsageState] = [:]
        for (key, state) in entries {
            guard !Self.isExpired(state, now: now) else { continue }
            // Marked on the way out, so a restored reading never presents as live.
            result[ProviderType(key)] = state.asCached()
        }
        return result
    }

    /// Whether a stored reading is too old to restore.
    ///
    /// A reading with no timestamp is dropped rather than trusted: we cannot show that it
    /// is recent, and the whole point of the bound is not to display figures we cannot
    /// date.
    static func isExpired(_ state: UsageState, now: Date) -> Bool {
        guard let lastUpdated = state.lastUpdated else { return true }
        return now.timeIntervalSince(lastUpdated) > maximumAge
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
