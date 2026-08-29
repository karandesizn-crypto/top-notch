import Foundation

/// Per-provider alert thresholds. Defaults match `backend/supabase/schema.sql`.
public struct UsageThresholds: Codable, Sendable, Equatable {
    public var warning: Double
    public var critical: Double

    public static let `default` = UsageThresholds(warning: 80, critical: 90)

    public init(warning: Double = 80, critical: Double = 90) {
        self.warning = warning
        self.critical = critical
    }
}
