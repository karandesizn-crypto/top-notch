import Foundation
import Observation
import SideNotchCore
import ProviderKit

/// Polls every provider and holds the latest snapshots for the UI.
///
/// Adapters read files other apps own, so a refresh is cheap but not free; the interval is
/// deliberately unhurried. Nothing here knows how any provider is read — that stays behind
/// `UsageProvider`.
@Observable
@MainActor
final class UsageStore {
    private(set) var snapshotsByProvider: [ProviderID: [UsageSnapshot]] = [:]
    private(set) var lastRefresh: Date?
    /// Ticks so countdown text re-renders without a full provider refresh.
    private(set) var now: Date = Date()

    let staleness = StalenessPolicy.default
    /// Rail order, fixed so rings never reshuffle under the cursor.
    let order: [ProviderID] = [.claude, .codex, .cursor]

    private let providers: [any UsageProvider]
    private let refreshInterval: TimeInterval
    private var refreshTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(providers: [any UsageProvider]? = nil, refreshInterval: TimeInterval = 60) {
        self.providers = providers ?? [ClaudeProvider(), CodexProvider(), CursorProvider()]
        self.refreshInterval = refreshInterval
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.now = Date()
            }
        }
    }

    func stop() {
        refreshTask?.cancel(); refreshTask = nil
        tickTask?.cancel(); tickTask = nil
    }

    func refresh() async {
        await withTaskGroup(of: (ProviderID, [UsageSnapshot]).self) { group in
            for provider in providers {
                group.addTask {
                    let snapshots = (try? await provider.fetchSnapshots()) ?? []
                    return (provider.id, snapshots)
                }
            }
            for await (id, snapshots) in group {
                // A failed read leaves the previous reading in place rather than blanking
                // the rail; staleness marking already tells the user it is old.
                if !snapshots.isEmpty { snapshotsByProvider[id] = snapshots }
            }
        }
        now = Date()
        lastRefresh = now
    }

    func snapshots(for provider: ProviderID) -> [UsageSnapshot] {
        snapshotsByProvider[provider] ?? []
    }

    /// The reading the rail ring shows: the most constrained active window, so the ring
    /// always reflects whichever limit will bite first.
    func headline(for provider: ProviderID) -> UsageSnapshot? {
        let snapshots = self.snapshots(for: provider)
        return snapshots
            .filter { $0.percentageUsed != nil }
            .max { ($0.percentageUsed ?? 0) < ($1.percentageUsed ?? 0) }
            ?? snapshots.first
    }

    func isStale(_ snapshot: UsageSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return staleness.isStale(snapshot, now: now)
    }
}
