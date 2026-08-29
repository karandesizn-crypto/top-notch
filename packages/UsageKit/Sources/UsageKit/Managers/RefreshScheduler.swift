import Foundation
import ProviderKit

/// Decides *when* usage is re-read. It knows nothing about how.
///
/// Extracted from the manager so the timing policy can be reasoned about — and later
/// extended with the rest of the lifecycle — without touching provider code. The scheduler
/// calls back; whoever owns the providers does the fetching.
@MainActor
public final class RefreshScheduler {
    /// Why a refresh is happening. Recorded so the manager can treat a user-initiated
    /// refresh differently from a background one if it ever needs to.
    public enum Trigger: String {
        case launch
        case manual
        case expansion
        case periodic
        case providerEvent
    }

    /// How long between periodic refreshes, read fresh each cycle so a settings change
    /// takes effect without restarting the loop.
    private let interval: @MainActor () -> TimeInterval
    private let perform: @MainActor (Trigger) async -> Void
    /// Fires periodically so countdown text re-renders without re-reading providers.
    private let tick: @MainActor () -> Void

    private var periodicTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    /// Guards against a second refresh starting while one is still running — the reason
    /// a burst of triggers cannot pile up into overlapping reads.
    private var isRefreshing = false

    public init(
        interval: @escaping @MainActor () -> TimeInterval,
        tick: @escaping @MainActor () -> Void,
        perform: @escaping @MainActor (Trigger) async -> Void
    ) {
        self.interval = interval
        self.tick = tick
        self.perform = perform
    }

    /// Starts the periodic loop and performs the launch refresh.
    public func start() {
        guard periodicTask == nil else { return }

        periodicTask = Task { [weak self] in
            guard let self else { return }
            await request(.launch)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval()))
                guard !Task.isCancelled else { return }
                await request(.periodic)
            }
        }

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    public func stop() {
        periodicTask?.cancel(); periodicTask = nil
        tickTask?.cancel(); tickTask = nil
    }

    /// Requests a refresh, dropping it if one is already in flight.
    ///
    /// Coalescing here rather than in the manager means every trigger — launch, a click,
    /// a provider event — gets the same protection without each remembering to ask.
    public func request(_ trigger: Trigger) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await perform(trigger)
    }
}
