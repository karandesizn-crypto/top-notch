import Foundation
import SideNotchCore

/// Live Codex usage, read through Codex's own app-server.
///
/// Detection is layered so the UI can say something specific: Codex missing entirely,
/// Codex present but never signed in, and Codex signed in but its app-server unreachable
/// are three different messages.
public final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    public let id: ProviderID = .codex
    public let displayName = "Codex"

    private let client: CodexAppServerClient
    private let thresholds: UsageThresholds
    /// Invoked when the app-server pushes a rate-limit update, so the app can refresh
    /// without waiting for its polling interval.
    private let onRateLimitsChanged: (@Sendable () async -> Void)?

    public init(
        thresholds: UsageThresholds = .default,
        onRateLimitsChanged: (@Sendable () async -> Void)? = nil
    ) {
        self.client = CodexAppServerClient()
        self.thresholds = thresholds
        self.onRateLimitsChanged = onRateLimitsChanged
    }

    public func start() async {
        guard let onRateLimitsChanged else { return }
        await client.setNotificationHandler { method in
            guard method == CodexAppServerClient.Method.rateLimitsUpdated else { return }
            Log.codex.debug("rate limits updated notification")
            await onRateLimitsChanged()
        }
    }

    public func stop() async {
        await client.stop()
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard CodexInstallation.isInstalled else { throw ProviderError.notInstalled }
        guard CodexInstallation.hasStoredAuth() else { throw ProviderError.authenticationRequired }

        try await client.start()

        let response: GetAccountRateLimitsResponse
        do {
            response = try await client.request(
                CodexAppServerClient.Method.readRateLimits,
                as: GetAccountRateLimitsResponse.self
            )
        } catch let error as ProviderError {
            throw error
        } catch {
            throw ProviderError.unknown(detail: "rate limit read failed")
        }

        // Token totals are a second, optional read: useful colour, but a failure here must
        // not cost the user their rate-limit figures.
        let tokenUsage = try? await client.request(
            CodexAppServerClient.Method.readTokenUsage,
            as: GetAccountTokenUsageResponse.self
        )

        let snapshot = CodexSnapshotMapper.snapshot(
            from: response, tokenUsage: tokenUsage, thresholds: thresholds
        )
        Log.codex.debug("read \(snapshot.windows.count) usage window(s)")
        return snapshot
    }
}
