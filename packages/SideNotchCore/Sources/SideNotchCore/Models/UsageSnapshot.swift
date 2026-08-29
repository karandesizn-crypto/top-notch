import Foundation

/// Whether a provider could be read at all.
public enum Availability: Codable, Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }

    public var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

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

/// One provider's usage at a point in time.
///
/// `windows` is a list rather than named fields because providers do not agree on which
/// windows exist. Codex may return a monthly window and no weekly one; Claude publishes a
/// 5-hour and a 7-day window. Anything that reaches for "the session window" by name will
/// break on the first provider that does not have one.
public struct UsageSnapshot: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let provider: ProviderID
    /// Plan name as the provider states it, e.g. "go", "pro".
    public let plan: String?
    public let windows: [UsageWindow]
    public let credits: CreditsInfo?
    public let availability: Availability
    public let lastUpdated: Date
    /// Provider-specific extras the UI may surface but Core does not interpret.
    /// Never put credentials or account identifiers here.
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        provider: ProviderID,
        plan: String? = nil,
        windows: [UsageWindow] = [],
        credits: CreditsInfo? = nil,
        availability: Availability = .available,
        lastUpdated: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.credits = credits
        self.availability = availability
        self.lastUpdated = lastUpdated
        self.metadata = metadata
    }

    /// A snapshot standing in for a provider that could not be read.
    public static func unavailable(
        provider: ProviderID, reason: String, at date: Date = Date()
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            availability: .unavailable(reason: reason),
            lastUpdated: date
        )
    }

    /// The window the rail should show: the closest to its limit.
    ///
    /// "Am I about to be cut off?" is answered by whichever window bites first, which is
    /// not necessarily the session one — a nearly exhausted weekly quota matters more than
    /// a fresh 5-hour window.
    public var headlineWindow: UsageWindow? {
        windows.filter { $0.usedFraction != nil }
            .max { ($0.usedFraction ?? 0) < ($1.usedFraction ?? 0) }
            ?? windows.first
    }

    /// Worst state across all windows, for the rail's semantic treatment.
    public var overallState: UsageState {
        guard availability.isAvailable else { return .unavailable }
        guard let worst = windows.compactMap({ $0.state }).max(by: { $0.severity < $1.severity })
        else { return .unavailable }
        return worst
    }
}

public extension UsageState {
    /// Ordering for "worst wins" comparisons and for detecting escalation between refreshes.
    var severity: Int {
        switch self {
        case .loading: 0
        case .unavailable: 1
        case .normal: 2
        case .warning: 3
        case .critical: 4
        case .exhausted: 5
        }
    }
}
