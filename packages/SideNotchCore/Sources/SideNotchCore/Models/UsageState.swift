import Foundation

/// Credit balance alongside the metered windows, where a provider offers one.
public struct CreditsInfo: Codable, Sendable, Equatable {
    public let hasCredits: Bool
    public let unlimited: Bool
    /// Provider-formatted balance. Kept as a string because providers send it that way and
    /// reformatting a currency we cannot identify would be worse than passing it through.
    public let balance: String?
    /// Reset credits available to clear a limit early, when offered.
    public let resetCreditsAvailable: Int?

    public init(
        hasCredits: Bool, unlimited: Bool,
        balance: String? = nil, resetCreditsAvailable: Int? = nil
    ) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
        self.resetCreditsAvailable = resetCreditsAvailable
    }
}

/// One provider's usage, and everything the UI needs to present it honestly.
///
/// Three facts are carried separately and never conflated:
///
/// - **What the figures say** — `windows`, and the `UsageLevel` on each.
/// - **Whether they could be obtained** — `status`.
/// - **Where they came from** — `source`.
///
/// A cached 90% and a live 90% are the same measurement from different places, and the UI
/// has to be able to say so without inferring it. Collapsing these into one enum is what
/// made a stale figure indistinguishable from a current one.
///
/// `windows` is a list rather than named fields because providers do not agree on which
/// windows exist. Anything reaching for "the session window" by name breaks on the first
/// provider that has none.
public struct UsageState: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let provider: ProviderType
    public let status: UsageStatus
    public let source: UsageSource
    /// When the figures were obtained. Nil when there are none.
    public let lastUpdated: Date?
    /// Why there are no figures, phrased for display. Never credentials or raw responses.
    public let failure: String?
    /// Plan name as the provider states it, e.g. "go", "pro".
    public let plan: String?
    public let windows: [UsageWindow]
    public let credits: CreditsInfo?
    /// Provider-specific extras the UI may surface but Core does not interpret.
    /// Never put credentials or account identifiers here.
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        provider: ProviderType,
        status: UsageStatus,
        source: UsageSource,
        lastUpdated: Date? = nil,
        failure: String? = nil,
        plan: String? = nil,
        windows: [UsageWindow] = [],
        credits: CreditsInfo? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.provider = provider
        self.status = status
        self.source = source
        self.lastUpdated = lastUpdated
        self.failure = failure
        self.plan = plan
        self.windows = windows
        self.credits = credits
        self.metadata = metadata
    }

    // MARK: Construction

    /// Figures read from the provider during this session.
    public static func live(
        provider: ProviderType,
        plan: String? = nil,
        windows: [UsageWindow],
        credits: CreditsInfo? = nil,
        metadata: [String: String] = [:],
        at date: Date = Date()
    ) -> UsageState {
        UsageState(
            provider: provider, status: .available, source: .live,
            lastUpdated: date, plan: plan, windows: windows,
            credits: credits, metadata: metadata
        )
    }

    /// The provider has no interface SideNotch can legitimately read. Retrying will not
    /// help, so this is deliberately distinct from `.unavailable`.
    public static func unsupported(
        provider: ProviderType, reason: String, at date: Date = Date()
    ) -> UsageState {
        UsageState(
            provider: provider, status: .unsupported, source: .unavailable,
            lastUpdated: date, failure: reason
        )
    }

    /// Present, but could not answer right now. Worth retrying.
    public static func unavailable(
        provider: ProviderType, reason: String, at date: Date = Date()
    ) -> UsageState {
        UsageState(
            provider: provider, status: .unavailable, source: .unavailable,
            lastUpdated: date, failure: reason
        )
    }

    /// The read failed in a way that is neither transient nor structural.
    public static func failed(
        provider: ProviderType, reason: String, at date: Date = Date()
    ) -> UsageState {
        UsageState(
            provider: provider, status: .error, source: .unavailable,
            lastUpdated: date, failure: reason
        )
    }

    /// Nothing known yet.
    public static func loading(provider: ProviderType) -> UsageState {
        UsageState(provider: provider, status: .loading, source: .unavailable)
    }

    /// The same figures, marked as having come from disk rather than a live read.
    ///
    /// Applied when restoring from the cache, so a reading's provenance survives a
    /// relaunch instead of silently presenting as current.
    public func asCached() -> UsageState {
        guard source == .live else { return self }
        return UsageState(
            id: id, provider: provider, status: status, source: .cached,
            lastUpdated: lastUpdated, failure: failure, plan: plan,
            windows: windows, credits: credits, metadata: metadata
        )
    }

    // MARK: Reading

    /// The window the rail shows: the closest to its limit.
    ///
    /// "Am I about to be cut off?" is answered by whichever window bites first, which is
    /// not necessarily the session one — a nearly exhausted weekly quota matters more than
    /// a fresh 5-hour window.
    public var headlineWindow: UsageWindow? {
        windows.filter { $0.usedFraction != nil }
            .max { ($0.usedFraction ?? 0) < ($1.usedFraction ?? 0) }
            ?? windows.first
    }

    public var usedPercentage: Double? { headlineWindow?.usedPercentage }
    public var remainingPercentage: Double? { usedPercentage.map { 100 - $0 } }
    public var resetDate: Date? { headlineWindow?.resetDate }
    public var windowDuration: TimeInterval? { headlineWindow?.duration }

    /// Worst level across all windows. Nil unless the provider actually answered.
    public var level: UsageLevel? {
        guard status == .available else { return nil }
        return windows.compactMap(\.level).max { $0.severity < $1.severity }
    }

    /// Whether figures should be drawn at all.
    public var hasFigures: Bool {
        status == .available && headlineWindow?.usedFraction != nil
    }
}
