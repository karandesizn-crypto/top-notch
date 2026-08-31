import Foundation
import Observation
import SideNotchCore
import ProviderKit

/// How a provider should be drawn.
///
/// A presentation concern, deliberately separate from the domain's `UsageStatus` and
/// `UsageLevel`: several distinct statuses share one visual treatment. `.unsupported`,
/// `.unavailable` and `.error` all render inert — what tells them apart is the message,
/// not the colour.
public enum ProviderDisplayState: String, Sendable {
    case normal, warning, critical, exhausted, unavailable, loading

    /// Whether figures should be drawn.
    public var hasMeasurement: Bool {
        switch self {
        case .normal, .warning, .critical, .exhausted: true
        case .unavailable, .loading: false
        }
    }

    public init(status: UsageStatus, level: UsageLevel?) {
        switch status {
        case .loading:
            self = .loading
        case .available:
            switch level {
            case .normal?: self = .normal
            case .warning?: self = .warning
            case .critical?: self = .critical
            case .exhausted?: self = .exhausted
            case nil: self = .unavailable
            }
        case .unavailable, .unsupported, .error:
            self = .unavailable
        }
    }
}

/// What the UI knows about one provider.
public struct ProviderStatus: Identifiable, Sendable {
    public let provider: ProviderType
    public let displayName: String
    /// The last state received, whatever its status or source.
    public var usage: UsageState
    public var isRefreshing: Bool

    public var id: ProviderType { provider }

    public var state: ProviderDisplayState {
        ProviderDisplayState(status: usage.status, level: usage.level)
    }

    public var headlineWindow: UsageWindow? { usage.headlineWindow }

    /// Where the figures came from, so the UI never has to infer it.
    public var source: UsageSource { usage.source }
    public var status: UsageStatus { usage.status }

    /// One-line explanation for the expanded view.
    public var statusMessage: String? {
        if let failure = usage.failure { return failure }
        if usage.status == .available && usage.windows.isEmpty {
            return "No metered limits on this plan"
        }
        return nil
    }
}

/// Owns the providers and holds what the UI renders.
///
/// Three properties matter: a failing provider never blocks another, a failure never
/// discards the last good reading, and nothing here blocks the main thread — provider work
/// happens off it and only the result is published.
@Observable
@MainActor
public final class UsageManager {
    public private(set) var statuses: [ProviderType: ProviderStatus] = [:]
    public private(set) var lastRefresh: Date?
    /// Why the last whole refresh ran. Observable so the UI could surface it, and useful
    /// in logs when diagnosing an unexpected read.
    public private(set) var lastTrigger: RefreshTrigger?
    /// Ticks so countdowns re-render without re-reading providers.
    public private(set) var now: Date = Date()

    #if DEBUG
    /// Pins the clock so offscreen renders reproduce exactly.
    ///
    /// Countdown text is derived from `now`, and the mock fixtures set their resets
    /// relative to launch — so a golden render taken today and checked tomorrow disagreed
    /// on "51m" versus "50m", and on the weekday name for the multi-day windows. A design
    /// lock that cannot reproduce is not a lock; it is a nuisance that gets re-recorded
    /// until it means nothing.
    public func pinClockForRendering(_ date: Date) { now = date }
    #endif

    /// Presentation order: the built-ins, then whatever the user added. Fixed, so chips
    /// never reshuffle under the pointer as readings arrive.
    public private(set) var order: [ProviderType] = []

    public let staleness = StalenessPolicy.default

    /// Shortest time a refresh is allowed to appear to take: one full turn of the sweep.
    ///
    /// A local read can return in milliseconds, which would make the ring's sweep a flash.
    /// Matching the sweep's own period means it completes a revolution. This delays only
    /// the indicator; figures are published the moment they arrive.
    public static let minimumVisibleRefresh: Duration = .milliseconds(1300)

    /// The hold this instance applies. Injectable so tests are not slowed by a constant
    /// that exists purely for how an animation reads.
    private let indicatorHold: Duration

    private let settings: AppSettings
    private let cache: any UsageCaching
    private let notifications: NotificationService
    private var providers: [ProviderType: any UsageProvider] = [:]
    private let registry: ProviderRegistry
    private var inFlight: Set<ProviderType> = []
    private let providerEvents = ProviderEventRelay()
    private var scheduler: RefreshScheduler?

    public init(
        settings: AppSettings,
        cache: any UsageCaching,
        notifications: NotificationService,
        registry: ProviderRegistry = .standard,
        indicatorHold: Duration = UsageManager.minimumVisibleRefresh,
        providerOverride: [any UsageProvider]? = nil
    ) {
        self.indicatorHold = indicatorHold
        self.settings = settings
        self.cache = cache
        self.notifications = notifications
        self.registry = registry

        let built = providerOverride ?? Self.makeProviders(settings: settings, registry: registry, relay: providerEvents)
        for provider in built { providers[provider.providerType] = provider }
        order = built.map(\.providerType)

        // Codex pushes `account/rateLimits/updated`; route it into a refresh so usage
        // changes appear without waiting out the interval. The trigger box exists because
        // providers are built before `self` is available.
        providerEvents.handler = { [weak self] in
            await self?.refresh(.codex, trigger: .providerEvent)
        }

        // Restored readings arrive already marked `.cached`.
        let cached = cache.load()
        for id in order {
            guard let provider = providers[id] else { continue }
            statuses[id] = ProviderStatus(
                provider: id,
                displayName: provider.displayName,
                usage: cached[id] ?? UsageState.loading(provider: id),
                isRefreshing: false
            )
        }
    }

    /// Built-ins in shipped order, then one adapter per user-added tool.
    ///
    /// Every adapter comes from the registry, so the manager never names a concrete
    /// provider type and adding an integration does not touch this file.
    private static func makeProviders(
        settings: AppSettings, registry: ProviderRegistry, relay: ProviderEventRelay
    ) -> [any UsageProvider] {
        let types = ProviderType.builtIn + settings.customProviders.map(\.providerType)
        return types.map { type in
            registry.make(
                ProviderRegistry.Context(
                    providerType: type,
                    displayName: settings.displayName(for: type),
                    thresholds: settings.thresholds,
                    onProviderEvent: { await relay.fire() }
                )
            )
        }
    }

    // MARK: Lifecycle

    public func start() async {
        guard scheduler == nil else { return }
        for provider in providers.values { await provider.startMonitoring() }

        let scheduler = RefreshScheduler(
            interval: { [weak self] in self?.settings.refreshInterval ?? 300 },
            tick: { [weak self] in self?.now = Date() },
            perform: { [weak self] trigger in await self?.refreshAll(trigger: trigger) }
        )
        self.scheduler = scheduler
        scheduler.start()
    }

    public func stop() async {
        scheduler?.stop()
        scheduler = nil
        for provider in providers.values { await provider.stopMonitoring() }
    }

    /// Rebuilds the provider list after the user adds or removes one.
    ///
    /// Existing readings are kept, so adding a provider does not blank what is on screen.
    public func rebuildProviders() async {
        for provider in providers.values where !ProviderType.builtIn.contains(provider.providerType) {
            await provider.stopMonitoring()
        }
        let rebuilt = Self.makeProviders(settings: settings, registry: registry, relay: providerEvents)
        var next: [ProviderType: any UsageProvider] = [:]
        for provider in rebuilt {
            // Built-in adapters are reused, so the Codex app-server connection survives a
            // settings change.
            next[provider.providerType] = providers[provider.providerType] ?? provider
        }
        providers = next
        order = rebuilt.map(\.providerType)

        for provider in rebuilt where statuses[provider.providerType] == nil {
            statuses[provider.providerType] = ProviderStatus(
                provider: provider.providerType,
                displayName: settings.displayName(for: provider.providerType),
                usage: UsageState.loading(provider: provider.providerType),
                isRefreshing: false
            )
        }
        statuses = statuses.filter { order.contains($0.key) }
    }

    // MARK: Refreshing

    public func refreshAll(trigger: RefreshTrigger = .manual) async {
        await withTaskGroup(of: Void.self) { group in
            for id in order where settings.isEnabled(id) {
                group.addTask { [weak self] in await self?.refresh(id, trigger: trigger) }
            }
        }
        lastTrigger = trigger
        now = Date()
        lastRefresh = now
    }

    /// Refreshes every visible provider, one shortly after the next.
    ///
    /// The stagger is the point: all the rings animate, but as a cascade rather than in
    /// unison, which reads as the surface responding rather than as a glitch.
    public func refreshAllStaggered(step: Duration = .milliseconds(90)) async {
        await withTaskGroup(of: Void.self) { group in
            for (index, id) in visibleProviders.enumerated() {
                group.addTask { [weak self] in
                    try? await Task.sleep(for: step * index)
                    await self?.refresh(id, trigger: .manual)
                }
            }
        }
    }

    /// Refreshes one provider. Safe to call concurrently; duplicates are dropped.
    ///
    /// Single-provider reads guard themselves rather than going through the scheduler.
    /// The scheduler coalesces *whole* refreshes; routing a Codex push through it would
    /// re-read Claude and Cursor as well, for an event that says nothing about them.
    public func refresh(
        _ id: ProviderType, trigger: RefreshTrigger = .manual
    ) async {
        guard let provider = providers[id], !inFlight.contains(id) else { return }
        inFlight.insert(id)
        statuses[id]?.isRefreshing = true
        let started = ContinuousClock.now
        defer {
            inFlight.remove(id)
            statuses[id]?.isRefreshing = false
        }

        let result: UsageState
        do {
            result = try await provider.fetchUsage()
        } catch let error as ProviderError {
            result = Self.state(for: error, provider: id)
            Log.provider.notice(
                "\(id.rawValue, privacy: .public) \(error.status.rawValue, privacy: .public) via \(trigger.rawValue, privacy: .public)"
            )
        } catch {
            result = UsageState.failed(provider: id, reason: "Unexpected failure")
        }

        apply(result, to: id, displayName: provider.displayName)

        // Hold the indicator long enough to be seen, without delaying the data — the
        // figures above are already published by this point.
        let elapsed = ContinuousClock.now - started
        if elapsed < indicatorHold {
            try? await Task.sleep(for: indicatorHold - elapsed)
        }
    }

    /// Records a new state, keeping the last good reading when the new one carries none.
    ///
    /// A transient failure must not blank a figure the user was reading; a *structural*
    /// one must, because an unsupported provider will never produce a newer reading and a
    /// cached figure would sit there looking current forever.
    private func apply(_ state: UsageState, to id: ProviderType, displayName: String) {
        let previous = statuses[id]?.usage

        if state.status == .available {
            cache.save(state)
            statuses[id]?.usage = state
            notifications.evaluate(
                state, displayName: displayName, enabled: settings.notificationsEnabled
            )
            return
        }

        // A provider can report "no figures" as an authoritative answer rather than a
        // failure — Cursor does exactly this when the account has no metered pool: the
        // request succeeded, and the truthful result is that nothing is metered. Papering
        // that over with the last cached percentage would show a number the account no
        // longer has, which is precisely the substitution the cache exists to prevent in
        // the other direction.
        //
        // So a successful read always wins, even when what it found is nothing.
        let readSucceeded = state.metadata["readSucceeded"] == "true"

        let keepsPreviousFigures = !readSucceeded
            && state.status.isRetryable
            && previous?.status == .available
        statuses[id]?.usage = keepsPreviousFigures ? (previous?.asCached() ?? state) : state
    }

    private static func state(for error: ProviderError, provider: ProviderType) -> UsageState {
        let reason = error.userFacingDescription
        switch error.status {
        case .unsupported: return .unsupported(provider: provider, reason: reason)
        case .error: return .failed(provider: provider, reason: reason)
        default: return .unavailable(provider: provider, reason: reason)
        }
    }

    // MARK: Queries

    public var visibleProviders: [ProviderType] {
        order.filter { settings.isEnabled($0) && statuses[$0] != nil }
    }

    public func status(for id: ProviderType) -> ProviderStatus? { statuses[id] }

    /// Whether a reading is old enough to mark. Only meaningful for figures that exist.
    public func isStale(_ id: ProviderType) -> Bool {
        guard let usage = statuses[id]?.usage, usage.status == .available else { return false }
        return staleness.isStale(usage, now: now)
    }
}

/// Lets a provider signal "my figures changed" before the manager that handles it exists.
///
/// Providers are constructed inside the manager's initializer, so they cannot capture
/// `self`. A push arriving in that window is dropped, which is correct — the launch
/// refresh is moments away.
public final class ProviderEventRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (@Sendable () async -> Void)?

    public var handler: (@Sendable () async -> Void)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    public func fire() async { await handler?() }
}
