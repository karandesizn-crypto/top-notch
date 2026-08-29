import Foundation

/// Alert thresholds, as fractions of a window.
public struct UsageThresholds: Codable, Sendable, Equatable {
    public var warning: Double
    public var critical: Double

    /// Defaults chosen so the ring reads the way the product's visual reference does:
    /// a fifth of a window used is calm, half is worth noticing, three quarters is hot.
    ///
    /// These are lower than the 80/90 in `backend/supabase/schema.sql`. That value is a
    /// reasonable alerting threshold but makes 73% render as "normal" green, which
    /// contradicts the design. Rather than give the ring its own colour ramp — two systems
    /// that can disagree — the single threshold set moves, and both the ring and the
    /// alerts follow it. The user can change both in Settings.
    ///
    /// Notification volume stays bounded regardless: alerts fire once per escalation per
    /// window, so a window produces at most one warning and one critical.
    public static let `default` = UsageThresholds(warning: 0.50, critical: 0.70)

    public init(warning: Double = 0.50, critical: Double = 0.70) {
        self.warning = warning
        self.critical = critical
    }
}

/// Derives `UsageState` from a measurement.
public enum UsageStateEvaluator {
    /// An absent measurement yields `.unavailable`, never `.normal` — an unknown reading
    /// must not be reported as healthy.
    public static func state(
        forUsedFraction fraction: Double?,
        thresholds: UsageThresholds = .default
    ) -> UsageState {
        guard let fraction else { return .unavailable }
        if fraction >= 1 { return .exhausted }
        if fraction >= thresholds.critical { return .critical }
        if fraction >= thresholds.warning { return .warning }
        return .normal
    }
}
