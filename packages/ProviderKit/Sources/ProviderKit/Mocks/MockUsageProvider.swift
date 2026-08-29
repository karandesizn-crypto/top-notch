import Foundation
import SideNotchCore

/// Deterministic provider for previews, UI work, and tests.
///
/// Reachable only when the app is launched with `SIDENOTCH_MOCK=1`, and paired with an
/// in-memory cache so its figures can never reach the real one.
public struct MockUsageProvider: UsageProvider {
    public let providerType: ProviderType
    public let displayName: String
    private let result: Result<UsageState, ProviderError>

    public init(
        providerType: ProviderType,
        displayName: String,
        result: Result<UsageState, ProviderError>
    ) {
        self.providerType = providerType
        self.displayName = displayName
        self.result = result
    }

    public func fetchUsage() async throws -> UsageState {
        try result.get()
    }

    /// One provider per state, so every visual treatment has something to render.
    public static func showcase(now: Date = Date()) -> [MockUsageProvider] {
        [
            MockUsageProvider(providerType: .claude, displayName: "Claude", result: .success(
                UsageState.live(
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
                    at: now
                )
            )),
            MockUsageProvider(providerType: .codex, displayName: "Codex", result: .success(
                UsageState.live(
                    provider: .codex, plan: "go",
                    windows: [
                        UsageWindow.fromPercentage(
                            id: "primary", label: "30-day", percent: 91,
                            resetDate: now.addingTimeInterval(6 * 86400),
                            duration: 30 * 86400
                        )
                    ],
                    credits: CreditsInfo(hasCredits: false, unlimited: false, resetCreditsAvailable: 1),
                    at: now
                )
            )),
            MockUsageProvider(providerType: .cursor, displayName: "Cursor", result: .success(
                UsageState.unsupported(
                    provider: .cursor, reason: "Not exposed outside Cursor", at: now
                )
            )),
        ]
    }
}
