import Foundation

/// Alert thresholds, as fractions of a window.
public struct UsageThresholds: Codable, Sendable, Equatable {
    public var warning: Double
    public var critical: Double

    public static let `default` = UsageThresholds(warning: 0.80, critical: 0.90)

    public init(warning: Double = 0.80, critical: Double = 0.90) {
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
