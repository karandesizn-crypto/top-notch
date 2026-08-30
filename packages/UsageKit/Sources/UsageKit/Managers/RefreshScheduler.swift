import Foundation
import ProviderKit

/// Why a refresh is happening.
///
/// Declared at file scope rather than nested in the scheduler: a type nested inside a
/// `@MainActor` class inherits that isolation, which stops it crossing a task boundary —
/// exactly what a trigger has to do to reach a concurrent read.
public enum RefreshTrigger: String, Sendable, CaseIterable {
    /// The app just started.
    case launch
    /// The user asked, via the menu bar or by clicking a provider.
    case manual
    /// The surface was opened.
    case expansion
    /// The periodic schedule came round.
    case periodic
    /// A provider told us its figures changed.
    case providerEvent
    /// The machine woke from sleep.
    ///
    /// The wall-clock loop would catch this within `evaluationCeiling` anyway; this exists
    /// so it is caught *immediately*. Opening the lid and glancing at the notch is the
    /// single most common way this app gets read, and half a minute of hours-old
    /// percentages is exactly the moment it must not be wrong.
    case wake

    /// Whether a person is waiting for the result.
    ///
    /// The distinction decides what happens when the trigger arrives mid-refresh. A
    /// hover-driven trigger can be discarded with no one the wiser; a click cannot, because
    /// the user watched themselves ask and would see nothing happen.
    var isUserInitiated: Bool {
        switch self {
        case .manual: true
        case .launch, .expansion, .periodic, .providerEvent, .wake: false
        }
    }
}

/// Decides *when* usage is re-read. It knows nothing about how.
///
/// Extracted from the manager so the timing policy can be reasoned about without touching
/// provider code. The scheduler calls back; whoever owns the providers does the fetching.
///
/// ## Why the loop is driven by wall clock rather than by sleeping for the interval
///
/// The obvious loop — sleep for the refresh interval, refresh, repeat — is wrong on a
/// laptop, which is the only kind of machine this app runs on. `Task.sleep` does not
/// advance while the system is asleep, so closing the lid for eight hours and reopening it
/// leaves the rail showing eight-hour-old percentages, with the next refresh still a full
/// interval away. The figures would be confidently, invisibly wrong at exactly the moment
/// the user glances at them.
///
/// So the loop wakes at least every `evaluationCeiling` seconds and asks the wall clock
/// whether a refresh is due, rather than trusting elapsed sleep. Lid-open, a clock change,
/// and a suspended timer all resolve the same way, and none of it needs AppKit — which
/// keeps this whole policy testable with an injected clock.
@MainActor
public final class RefreshScheduler {
    /// Longest the loop will sleep before re-checking the clock.
    ///
    /// Also the cadence at which reset countdowns re-render, which is why it is not longer:
    /// "resets in 2h 14m" going stale for minutes at a time reads as a frozen app.
    static let evaluationCeiling: TimeInterval = 30

    /// Shortest sleep, so a misconfigured interval cannot spin the loop.
    static let minimumDelay: TimeInterval = 0.05

    /// How long between periodic refreshes, read fresh each cycle so a settings change
    /// takes effect without restarting the loop.
    private let interval: @MainActor () -> TimeInterval
    private let perform: @MainActor (RefreshTrigger) async -> Void
    /// Fires periodically so countdown text re-renders without re-reading providers.
    private let tick: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var loopTask: Task<Void, Never>?
    /// Guards against a second refresh starting while one is still running — the reason
    /// a burst of triggers cannot pile up into overlapping reads.
    private var isRefreshing = false
    /// At most one deferred follow-up, for a trigger a person is waiting on.
    private var pendingUserRequest: RefreshTrigger?
    /// Wall-clock time of the last completed refresh. The basis for every timing decision.
    private var lastRefreshAt: Date?

    public init(
        interval: @escaping @MainActor () -> TimeInterval,
        tick: @escaping @MainActor () -> Void,
        perform: @escaping @MainActor (RefreshTrigger) async -> Void,
        now: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.interval = interval
        self.tick = tick
        self.perform = perform
        self.now = now
        self.sleep = sleep
    }

    /// Starts the loop and performs the launch refresh.
    public func start() {
        guard loopTask == nil else { return }

        loopTask = Task { [weak self] in
            guard let self else { return }
            await request(.launch)
            while !Task.isCancelled {
                let delay = nextDelay()
                try? await sleep(.milliseconds(Int(delay * 1000)))
                guard !Task.isCancelled else { return }
                // Countdowns re-render every pass, whether or not a read is due.
                tick()
                if isOverdue() {
                    await request(.periodic)
                }
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        pendingUserRequest = nil
    }

    /// Requests a refresh, coalescing against one already in flight.
    ///
    /// Coalescing here rather than in the manager means every trigger — launch, a click, a
    /// provider event — gets the same protection without each remembering to ask.
    ///
    /// A trigger that arrives mid-refresh is dropped, with one exception: a user-initiated
    /// one is held and run once, afterwards. A click that silently does nothing is a bug
    /// the user can see, and "at most one follow-up" still prevents a burst of triggers
    /// becoming a burst of reads.
    public func request(_ trigger: RefreshTrigger) async {
        guard !isRefreshing else {
            if trigger.isUserInitiated {
                pendingUserRequest = trigger
            }
            return
        }

        isRefreshing = true
        await perform(trigger)
        lastRefreshAt = now()
        isRefreshing = false

        if let pending = pendingUserRequest {
            pendingUserRequest = nil
            await request(pending)
        }
    }

    // MARK: Timing

    /// How long to sleep before the next evaluation.
    ///
    /// Capped at `evaluationCeiling` so the loop keeps checking the wall clock even when
    /// the configured interval is an hour away.
    private func nextDelay() -> TimeInterval {
        let target = interval()
        guard let lastRefreshAt else {
            return clamp(target)
        }
        let elapsed = now().timeIntervalSince(lastRefreshAt)
        // A negative elapsed means the clock moved backwards; refresh promptly rather
        // than waiting out an interval that may never arrive.
        guard elapsed >= 0 else { return Self.minimumDelay }
        return clamp(target - elapsed)
    }

    private func clamp(_ delay: TimeInterval) -> TimeInterval {
        min(max(delay, Self.minimumDelay), Self.evaluationCeiling)
    }

    /// Whether enough wall-clock time has passed to warrant a read.
    private func isOverdue() -> Bool {
        guard let lastRefreshAt else { return true }
        let elapsed = now().timeIntervalSince(lastRefreshAt)
        // Backwards clock: treat as due. Waiting would be a bet on a clock we just saw
        // misbehave.
        guard elapsed >= 0 else { return true }
        return elapsed >= interval()
    }
}
