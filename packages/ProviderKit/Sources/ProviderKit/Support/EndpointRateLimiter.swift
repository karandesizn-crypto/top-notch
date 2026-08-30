import Foundation

/// Decides whether a provider endpoint may be called right now.
///
/// This exists because of a specific, documented failure. Anthropic's usage endpoint
/// rate-limits far more aggressively than its polling value suggests: a short burst earns
/// an HTTP 429 that persists for hours, it sends no `Retry-After` to negotiate with, and
/// the issue asking for a documented safe interval was closed as not planned. A refresh
/// on every hover would take the user's usage readout offline for the rest of the
/// afternoon — and, worse, do it silently, since the last good figures would still be
/// sitting in the cache looking current.
///
/// So the floor is enforced here rather than left to callers. `RefreshScheduler` can ask
/// as often as the UI wants; requests that arrive early are refused locally and cost
/// nothing.
///
/// Failing closed is deliberate. A refused call surfaces the cached reading marked
/// `.cached`, which is honest, where an allowed call risks a 429 that surfaces nothing.
public actor EndpointRateLimiter {
    /// Shortest gap between two successful calls.
    private let minimumInterval: TimeInterval
    /// First penalty after a 429.
    private let initialBackoff: TimeInterval
    /// Ceiling the penalty doubles toward.
    private let maximumBackoff: TimeInterval

    private var lastAttempt: Date?
    private var blockedUntil: Date?
    private var currentBackoff: TimeInterval

    /// Defaults are the interval a comparable tool settled on after hitting the limit in
    /// production (180s poll, 5→30 minute backoff), not a guess.
    public init(
        minimumInterval: TimeInterval = 180,
        initialBackoff: TimeInterval = 300,
        maximumBackoff: TimeInterval = 1800
    ) {
        self.minimumInterval = minimumInterval
        self.initialBackoff = initialBackoff
        self.maximumBackoff = maximumBackoff
        self.currentBackoff = initialBackoff
    }

    /// Why a call was refused, so the adapter can pick the right user-facing state.
    public enum Refusal: Equatable, Sendable {
        /// Called again too soon. The previous reading is still the best answer.
        case tooSoon(retryAfter: TimeInterval)
        /// The provider returned 429 and we are serving out the penalty.
        case backingOff(retryAfter: TimeInterval)
    }

    /// Consumes permission. On success the clock starts, so callers must actually perform
    /// the request after a `nil` return.
    public func claim(now: Date = Date()) -> Refusal? {
        if let blockedUntil, now < blockedUntil {
            return .backingOff(retryAfter: blockedUntil.timeIntervalSince(now))
        }
        if let lastAttempt {
            let elapsed = now.timeIntervalSince(lastAttempt)
            if elapsed < minimumInterval {
                return .tooSoon(retryAfter: minimumInterval - elapsed)
            }
        }
        lastAttempt = now
        return nil
    }

    /// Clears any penalty and resets the ladder.
    public func recordSuccess() {
        blockedUntil = nil
        currentBackoff = initialBackoff
    }

    /// Applies the next penalty, doubling toward the ceiling.
    ///
    /// `retryAfter` is honoured when the provider sends one, but the endpoint in question
    /// does not, which is why the ladder exists.
    public func recordRateLimited(retryAfter: TimeInterval? = nil, now: Date = Date()) {
        let penalty = retryAfter ?? currentBackoff
        blockedUntil = now.addingTimeInterval(penalty)
        currentBackoff = min(currentBackoff * 2, maximumBackoff)
    }

    /// A transport failure is not the provider's rate limiter talking, so it must not
    /// escalate the ladder — otherwise an hour offline would push us to the 30-minute
    /// ceiling and keep us there long after the network came back.
    public func recordTransportFailure() {}

    /// Test and diagnostic accessor. Never surfaced in the UI.
    public func backingOff(now: Date = Date()) -> Bool {
        guard let blockedUntil else { return false }
        return now < blockedUntil
    }
}
