import Foundation

/// One limit window within a provider's usage — a rolling session, a weekly quota, a
/// monthly cap.
///
/// Fractions rather than percentages, so normalization happens once at the provider
/// boundary instead of at every call site.
public struct UsageWindow: Codable, Sendable, Identifiable, Equatable {
    /// Stable key within a snapshot, e.g. "primary". Used for diffing across refreshes.
    public let id: String
    public let label: String
    /// 0...1 when known. Nil means the provider exposes no measurement for this window.
    public let usedFraction: Double?
    public let resetDate: Date?
    /// Length of this window, when the provider states it.
    public let duration: TimeInterval?
    public let level: UsageLevel?

    public init(
        id: String,
        label: String,
        usedFraction: Double?,
        resetDate: Date? = nil,
        duration: TimeInterval? = nil,
        level: UsageLevel?
    ) {
        self.id = id
        self.label = label
        self.usedFraction = usedFraction.map { UsageWindow.normalize($0) }
        self.resetDate = resetDate
        self.duration = duration
        self.level = level
    }

    /// Whether the window this figure describes has already reset.
    ///
    /// A percentage is a statement about a specific window, and it stops being true the
    /// moment that window rolls over. A live reading always resets in the future, so this
    /// only ever fires on a figure that has been held over from an earlier read — which is
    /// exactly when it stops meaning anything.
    ///
    /// A window with no stated reset cannot expire: nothing is known about when it rolls
    /// over, and guessing would be worse than holding it.
    public func hasExpired(now: Date = Date()) -> Bool {
        guard let resetDate else { return false }
        return resetDate <= now
    }

    public var remainingFraction: Double? {
        usedFraction.map { 1 - $0 }
    }

    public var usedPercentage: Double? {
        usedFraction.map { $0 * 100 }
    }

    public var reset: ResetInfo? {
        resetDate.map { ResetInfo(date: $0, windowDuration: duration) }
    }

    /// Clamps to 0...1.
    ///
    /// Providers can report over 100% — Codex's `usedPercent` is a plain integer with no
    /// documented ceiling — and an unclamped value would drive a ring past a full turn.
    /// Clamping here means no view has to defend against it.
    public static func normalize(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Builds a window from a provider's integer percentage.
    public static func fromPercentage(
        id: String,
        label: String,
        percent: Double?,
        resetDate: Date? = nil,
        duration: TimeInterval? = nil,
        thresholds: UsageThresholds = .default
    ) -> UsageWindow {
        let fraction = percent.map { $0 / 100 }
        return UsageWindow(
            id: id,
            label: label,
            usedFraction: fraction,
            resetDate: resetDate,
            duration: duration,
            level: UsageLevelEvaluator.level(forUsedFraction: fraction, thresholds: thresholds)
        )
    }
}
