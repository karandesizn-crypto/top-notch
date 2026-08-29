import Foundation
import SideNotchCore

/// Deterministic provider for previews, UI work, and tests.
public struct MockUsageProvider: UsageProvider {
    public let id: ProviderID
    public let displayName: String
    private let result: Result<UsageSnapshot, ProviderError>

    public init(id: ProviderID, displayName: String, result: Result<UsageSnapshot, ProviderError>) {
        self.id = id
        self.displayName = displayName
        self.result = result
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        try result.get()
    }

    /// One provider per state, so every visual treatment has something to render.
    public static func showcase(now: Date = Date()) -> [MockUsageProvider] {
        [
            MockUsageProvider(id: .claude, displayName: "Claude", result: .success(
                UsageSnapshot(
                    provider: .claude, plan: "max",
                    windows: [
                        UsageWindow.fromPercentage(
                            id: "primary", label: "5-hour", percent: 73,
                            resetDate: now.addingTimeInterval(51 * 60),
                            duration: 5 * 3600
                        ),
                        UsageWindow.fromPercentage(
                            id: "secondary", label: "Weekly", percent: 21,
                            resetDate: now.addingTimeInterval(3 * 86400),
                            duration: 7 * 86400
                        ),
                    ],
                    lastUpdated: now
                )
            )),
            MockUsageProvider(id: .codex, displayName: "Codex", result: .success(
                UsageSnapshot(
                    provider: .codex, plan: "go",
                    windows: [
                        UsageWindow.fromPercentage(
                            id: "primary", label: "30-day", percent: 91,
                            resetDate: now.addingTimeInterval(6 * 86400),
                            duration: 30 * 86400
                        )
                    ],
                    credits: CreditsInfo(hasCredits: false, unlimited: false, resetCreditsAvailable: 1),
                    lastUpdated: now
                )
            )),
            MockUsageProvider(id: .cursor, displayName: "Cursor", result: .failure(
                .unsupported(reason: "Cursor does not expose usage outside its own app")
            )),
        ]
    }
}
