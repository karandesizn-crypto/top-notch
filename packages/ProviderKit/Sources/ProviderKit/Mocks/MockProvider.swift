import Foundation
import SideNotchCore

/// Deterministic snapshots for design work, previews, and UI tests.
///
/// Phase 2 of the build plan builds the design system against mock data only; this is that
/// source. Dates are relative to a fixed `now` so a preview never drifts.
public struct MockProvider: UsageProvider {
    public let id: ProviderID
    private let snapshots: [UsageSnapshot]

    public init(id: ProviderID, snapshots: [UsageSnapshot]) {
        self.id = id
        self.snapshots = snapshots
    }

    public func fetchSnapshots() async throws -> [UsageSnapshot] { snapshots }

    /// One provider per health state, so every visual treatment has something to render.
    public static func showcase(now: Date = Date()) -> [MockProvider] {
        [
            MockProvider(id: .claude, snapshots: [
                UsageSnapshot(
                    provider: .claude, percentageUsed: 50, remainingEstimate: 50,
                    resetAt: now.addingTimeInterval(2 * 3600 + 14 * 60), scope: .session,
                    health: .healthy, observedAt: now, source: .mock,
                    windowLabel: "5-hour session"
                ),
                UsageSnapshot(
                    provider: .claude, percentageUsed: 92, remainingEstimate: 8,
                    resetAt: now.addingTimeInterval(3 * 86400), scope: .weekly,
                    health: .critical, observedAt: now, source: .mock,
                    windowLabel: "Weekly (all models)"
                ),
            ]),
            MockProvider(id: .codex, snapshots: [
                UsageSnapshot(
                    provider: .codex, percentageUsed: 35, remainingEstimate: 65,
                    resetAt: now.addingTimeInterval(6 * 86400), scope: .monthly,
                    health: .healthy, observedAt: now, source: .mock,
                    windowLabel: "30-day", detail: "Plan: go"
                )
            ]),
            MockProvider(id: .cursor, snapshots: [
                UsageSnapshot(
                    provider: .cursor, scope: .session, health: .unavailable,
                    observedAt: now, source: .mock, windowLabel: "Not exposed locally",
                    detail: "Cursor keeps usage server-side."
                )
            ]),
        ]
    }
}
