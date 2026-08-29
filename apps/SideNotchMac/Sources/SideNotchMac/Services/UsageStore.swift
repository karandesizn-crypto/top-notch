import Foundation
import Observation
import SideNotchCore
import ProviderKit

/// What the UI knows about one provider.
struct ProviderStatus: Identifiable, Sendable {
    let provider: ProviderID
    let displayName: String
    var snapshot: UsageSnapshot?
    var error: ProviderError?
    var isRefreshing: Bool

    var id: ProviderID { provider }

    /// State for the rail ring.
    ///
    /// A cached snapshot outranks `loading`, so a refresh does not blank a ring the user
    /// was reading. An error only replaces a snapshot when there is no snapshot to keep.
    var state: UsageState {
        if let snapshot, snapshot.availability.isAvailable, !snapshot.windows.isEmpty {
            return snapshot.overallState
        }
        if error != nil { return .unavailable }
        return isRefreshing ? .loading : .unavailable
    }

    var headlineWindow: UsageWindow? { snapshot?.headlineWindow }

    /// One-line explanation for the detail card.
    var statusMessage: String? {
        if let error { return error.userFacingDescription }
        if let snapshot, snapshot.windows.isEmpty { return "No metered limits on this plan" }
        return snapshot?.availability.reason
    }
}

/// Coordinates the providers and holds what the UI renders.
///
/// Three properties matter here: a failing provider never blocks another, a failure never
/// discards the last good reading, and nothing on this path can block the main thread —
/// provider work happens off it and only the result is published.
@Observable
@MainActor
final class UsageStore {
    private(set) var statuses: [ProviderID: ProviderStatus] = [:]
    private(set) var lastRefresh: Date?
    /// Ticks so countdowns re-render without re-reading providers.
    private(set) var now: Date = Date()

    /// Presentation order: the three built-ins, then whatever the user added. Fixed, so
    /// chips never reshuffle under the pointer as readings arrive.
    private(set) var order: [ProviderID] = []

    let staleness = StalenessPolicy.default

    private let settings: AppSettings
    private let cache: SnapshotCache
    private let notifications: NotificationService
    private var providers: [ProviderID: any UsageProvider] = [:]
    private var refreshTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var inFlight: Set<ProviderID> = []
    private let refreshTrigger = RefreshTrigger()

    init(
        settings: AppSettings,
        cache: SnapshotCache,
        notifications: NotificationService,
        providerOverride: [any UsageProvider]? = nil
    ) {
        self.settings = settings
        self.cache = cache
        self.notifications = notifications

        let built = providerOverride ?? Self.makeProviders(settings: settings, trigger: refreshTrigger)
        for provider in built { providers[provider.id] = provider }
        order = built.map(\.id)

        // Codex pushes `account/rateLimits/updated`; route it straight into a refresh so
        // usage changes appear without waiting out the polling interval. The trigger box
        // exists because the provider is built before `self` is available.
        refreshTrigger.handler = { [weak self] in await self?.refresh(.codex) }

        let cached = cache.load()
        for id in order {
            guard let provider = providers[id] else { continue }
            statuses[id] = ProviderStatus(
                provider: id,
                displayName: provider.displayName,
                snapshot: cached[id],
                error: nil,
                isRefreshing: false
            )
        }
    }

    /// Built-ins in shipped order, then one `CustomUsageProvider` per user-added tool.
    private static func makeProviders(
        settings: AppSettings, trigger: RefreshTrigger
    ) -> [any UsageProvider] {
        var providers: [any UsageProvider] = [
            ClaudeUsageProvider(),
            CodexUsageProvider(thresholds: settings.thresholds) { await trigger.fire() },
            CursorUsageProvider(),
        ]
        for definition in settings.customProviders {
            providers.append(
                CustomUsageProvider(id: definition.providerID, displayName: definition.name)
            )
        }
        return providers
    }

    /// Rebuilds the provider list after the user adds or removes one.
    ///
    /// Existing snapshots are kept, so adding a provider does not blank the readings
    /// already on screen.
    func rebuildProviders() async {
        for provider in providers.values where !ProviderID.builtIn.contains(provider.id) {
            await provider.stop()
        }
        var rebuilt: [ProviderID: any UsageProvider] = [:]
        for provider in Self.makeProviders(settings: settings, trigger: refreshTrigger) {
            // Built-in adapters are reused; only the custom set is rebuilt, so the Codex
            // app-server connection survives a settings change.
            rebuilt[provider.id] = providers[provider.id] ?? provider
        }
        providers = rebuilt
        order = Self.makeProviders(settings: settings, trigger: refreshTrigger).map(\.id)

        for id in order where statuses[id] == nil {
            statuses[id] = ProviderStatus(
                provider: id,
                displayName: settings.displayName(for: id),
                snapshot: nil, error: nil, isRefreshing: false
            )
        }
        statuses = statuses.filter { order.contains($0.key) }
    }

    /// Wires the Codex push notification to a refresh, so usage changes land without
    /// waiting out the polling interval.
    func start() async {
        guard refreshTask == nil else { return }

        for provider in providers.values { await provider.start() }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                let interval = self?.settings.refreshInterval ?? 300
                try? await Task.sleep(for: .seconds(interval))
            }
        }

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.now = Date()
            }
        }
    }

    func stop() async {
        refreshTask?.cancel(); refreshTask = nil
        tickTask?.cancel(); tickTask = nil
        for provider in providers.values { await provider.stop() }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for id in order where settings.isEnabled(id) {
                group.addTask { [weak self] in await self?.refresh(id) }
            }
        }
        now = Date()
        lastRefresh = now
    }

    /// Shortest time a refresh is allowed to appear to take: one full turn of the sweep.
    ///
    /// A local read can return in a few milliseconds, which would make the ring's sweep a
    /// flash rather than an animation. Matching the sweep's own 1.3s period means it
    /// completes a revolution and comes to rest where it started, instead of stopping a
    /// third of the way round.
    ///
    /// This delays only the indicator. The figures are published the moment they arrive.
    static let minimumVisibleRefresh: Duration = .milliseconds(1300)

    /// Refreshes every visible provider, one shortly after the next.
    ///
    /// The stagger is the point: all the rings animate, but as a cascade rather than in
    /// unison, which reads as the surface responding rather than as a glitch.
    func refreshAllStaggered(step: Duration = .milliseconds(90)) async {
        await withTaskGroup(of: Void.self) { group in
            for (index, id) in visibleProviders.enumerated() {
                group.addTask { [weak self] in
                    try? await Task.sleep(for: step * index)
                    await self?.refresh(id)
                }
            }
        }
    }

    /// Refreshes one provider. Safe to call concurrently; duplicate requests are dropped.
    func refresh(_ id: ProviderID) async {
        guard let provider = providers[id], !inFlight.contains(id) else { return }
        inFlight.insert(id)
        statuses[id]?.isRefreshing = true
        let started = ContinuousClock.now
        defer {
            inFlight.remove(id)
            statuses[id]?.isRefreshing = false
        }

        do {
            let snapshot = try await provider.fetchSnapshot()
            statuses[id]?.snapshot = snapshot
            statuses[id]?.error = nil
            cache.save(snapshot)
            notifications.evaluate(
                snapshot,
                displayName: provider.displayName,
                enabled: settings.notificationsEnabled
            )
        } catch let error as ProviderError {
            statuses[id]?.error = error
            // A transient failure keeps the last good snapshot, marked stale. A permanent
            // one must not: an unsupported or uninstalled provider will never produce a
            // newer reading, so a cached figure would sit there looking live forever.
            if Self.isPermanent(error) { statuses[id]?.snapshot = nil }
            Log.provider.notice("\(id.rawValue, privacy: .public) unavailable: \(error.userFacingDescription, privacy: .public)")
        } catch {
            statuses[id]?.error = .unknown(detail: "unexpected failure")
        }

        // Hold the indicator long enough to be seen, without delaying the data itself —
        // the figures above are already published by this point.
        let elapsed = ContinuousClock.now - started
        if elapsed < Self.minimumVisibleRefresh {
            try? await Task.sleep(for: Self.minimumVisibleRefresh - elapsed)
        }
    }

    /// Whether a failure means "there will never be data" rather than "not right now".
    private static func isPermanent(_ error: ProviderError) -> Bool {
        switch error {
        case .unsupported, .notInstalled: true
        case .notRunning, .authenticationRequired, .network, .invalidResponse, .unknown: false
        }
    }

    // MARK: Queries

    var visibleProviders: [ProviderID] {
        order.filter { settings.isEnabled($0) && statuses[$0] != nil }
    }

    func status(for id: ProviderID) -> ProviderStatus? { statuses[id] }

    func isStale(_ id: ProviderID) -> Bool {
        guard let snapshot = statuses[id]?.snapshot else { return false }
        return staleness.isStale(snapshot, now: now)
    }
}


/// Lets a provider signal "refresh me" before the store that handles it exists.
///
/// Providers are constructed inside the store's initializer, so they cannot capture
/// `self`. This box is handed over at construction and given its handler once the store is
/// ready; a push arriving in that window is simply dropped, which is correct — the first
/// scheduled refresh is moments away.
final class RefreshTrigger: @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (@Sendable () async -> Void)?

    var handler: (@Sendable () async -> Void)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    func fire() async {
        await handler?()
    }
}
