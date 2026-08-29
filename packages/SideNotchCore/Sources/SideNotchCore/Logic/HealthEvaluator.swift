import Foundation

/// Derives `UsageHealth` from a percentage and a threshold set.
public enum HealthEvaluator {
    /// Returns `.unavailable` when the percentage is unknown — an unknown reading is never
    /// optimistically reported as healthy.
    public static func health(
        forPercentageUsed percentage: Double?,
        thresholds: UsageThresholds = .default
    ) -> UsageHealth {
        guard let percentage else { return .unavailable }
        if percentage >= 100 { return .exhausted }
        if percentage >= thresholds.critical { return .critical }
        if percentage >= thresholds.warning { return .warning }
        return .healthy
    }
}
