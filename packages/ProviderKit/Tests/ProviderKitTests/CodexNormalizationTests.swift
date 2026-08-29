import Testing
import Foundation
import SideNotchCore
@testable import ProviderKit

private func decodeFixture(_ name: String) throws -> GetAccountRateLimitsResponse {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name).json")
    return try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: Data(contentsOf: url))
}

@Suite("Codex response normalization")
struct CodexNormalizationTests {

    @Test("a live single-window reply maps to one window, not a fabricated pair")
    func primaryOnly() throws {
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-primary-only"))

        #expect(snapshot.provider == .codex)
        #expect(snapshot.plan == "go")
        #expect(snapshot.windows.count == 1)

        let window = try #require(snapshot.windows.first)
        #expect(window.id == "primary")
        #expect(window.usedFraction == 0)
        #expect(window.label == "30-day")          // derived from windowDurationMins 43200
        #expect(window.duration == 2_592_000)   // 43200 minutes
        #expect(window.level == .normal)
        #expect(snapshot.credits?.resetCreditsAvailable == 1)
    }

    @Test("percentages become fractions and both windows survive")
    func twoWindows() throws {
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-two-windows"))

        #expect(snapshot.windows.count == 2)
        let primary = try #require(snapshot.windows.first { $0.id == "primary" })
        #expect(abs((primary.usedFraction ?? 0) - 0.73) < 0.0001)
        #expect(abs((primary.remainingFraction ?? 0) - 0.27) < 0.0001)
        #expect(primary.label == "5-hour")

        let secondary = try #require(snapshot.windows.first { $0.id == "secondary" })
        #expect(abs((secondary.usedFraction ?? 0) - 0.21) < 0.0001)
        #expect(secondary.label == "Weekly")        // 10080 minutes
        #expect(snapshot.credits?.balance == "$4.20")
    }

    @Test("the headline window is the most constrained one")
    func headline() throws {
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-two-windows"))
        #expect(snapshot.headlineWindow?.id == "primary")   // 73% beats 21%
    }

    @Test("a reply with no windows is a successful read, not an error")
    func emptyResponse() throws {
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-empty"))
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.status == .available)
        #expect(snapshot.plan == nil)
        #expect(snapshot.level == nil)
    }

    @Test("a window with no duration falls back to a generic label rather than guessing")
    func missingDuration() throws {
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-spend-control"))
        let primary = try #require(snapshot.windows.first { $0.id == "primary" })
        #expect(primary.label == "Current window")
        #expect(primary.duration == nil)
        #expect(primary.resetDate == nil)
        #expect(primary.level == .critical)         // 96%
    }

    @Test("a spend control becomes its own window")
    func spendControl() throws {
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-spend-control"))
        let spend = try #require(snapshot.windows.first { $0.id == "individualLimit" })
        #expect(abs((spend.usedFraction ?? 0) - 0.85) < 0.0001)   // 15% remaining
        #expect(spend.label == "Spend limit")
        #expect(snapshot.metadata["spendUsed"] == "$85.00")
    }

    @Test("the metered bucket wins over the backward-compatible mirror")
    func prefersMeteredBucket() throws {
        // The fixture's mirror and bucket agree; assert we read the bucket by checking the
        // field only the bucket path populates end to end.
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-primary-only"))
        #expect(snapshot.metadata["limitId"] == "codex")
    }
}

@Suite("Usage level thresholds")
struct UsageLevelTests {
    // Precomputed: the compiler cannot type-check arithmetic inside `arguments`.
    static let boundaryCases: [(Double, UsageLevel)] = [
        (0.0, .normal), (0.21, .normal), (0.49, .normal),
        (0.50, .warning), (0.52, .warning), (0.69, .warning),
        (0.70, .critical), (0.73, .critical), (0.99, .critical),
        (1.0, .exhausted), (1.4, .exhausted),
    ]

    /// The boundaries encode the reference design: 21% calm, 52% noticed, 73% hot.
    @Test("state boundaries", arguments: UsageLevelTests.boundaryCases)
    func boundaries(fraction: Double, expected: UsageLevel) {
        #expect(UsageLevelEvaluator.level(forUsedFraction: fraction) == expected)
    }

    @Test("an absent measurement has no level, never normal")
    func absentIsUnavailable() {
        #expect(UsageLevelEvaluator.level(forUsedFraction: nil) == nil)
    }

    @Test("fractions are clamped so a ring cannot exceed a full turn")
    func clamping() {
        #expect(UsageWindow.normalize(1.4) == 1)
        #expect(UsageWindow.normalize(-0.2) == 0)
        #expect(UsageWindow.normalize(.nan) == 0)
        // Over-100% still reads as exhausted, and the ring stays full.
        let window = UsageWindow.fromPercentage(id: "p", label: "x", percent: 140)
        #expect(window.usedFraction == 1)
        #expect(window.level == .exhausted)
    }
}

@Suite("Provider errors")
struct ProviderErrorTests {
    @Test("an unknown JSON-RPC method reads as an interface change")
    func unknownMethod() {
        let error = CodexAppServerClient.providerError(forRPCCode: -32601, message: "Method not found")
        #expect(error == .unsupported(reason: "Codex no longer exposes this method"))
    }

    @Test("auth wording maps to authenticationRequired")
    func authError() {
        #expect(CodexAppServerClient.providerError(forRPCCode: 401, message: "Unauthorized") == .authenticationRequired)
        #expect(CodexAppServerClient.providerError(forRPCCode: 1, message: "Please sign in to continue") == .authenticationRequired)
    }

    @Test("other errors do not leak the server message")
    func opaqueError() {
        let error = CodexAppServerClient.providerError(forRPCCode: 500, message: "secret detail /Users/x/thing")
        #expect(error == .invalidResponse(detail: "app-server error 500"))
        #expect(!error.userFacingDescription.contains("secret"))
    }

    @Test("stub providers report unsupported with a reason")
    func stubs() async {
        for provider: any UsageProvider in [ClaudeUsageProvider(), CursorUsageProvider()] {
            // Stubs report unsupported rather than throwing, so the UI can say why.
            let state = try? await provider.fetchUsage()
            #expect(state?.status == .unsupported)
        }
    }

    @Test("mock unsupported surfaces through the protocol")
    func mockUnsupported() async throws {
        let cursor = try #require(
            MockUsageProvider.showcase().first { $0.providerType == .cursor }
        )
        let state = try await cursor.fetchUsage()
        #expect(state.status == .unsupported)
        #expect(state.source == .unavailable)
    }
}

@Suite("Codex token usage")
struct CodexTokenUsageTests {
    private func usageFixture() throws -> GetAccountTokenUsageResponse {
        let url = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/token-usage.json")
        return try JSONDecoder().decode(
            GetAccountTokenUsageResponse.self, from: Data(contentsOf: url)
        )
    }

    /// Local noon on 2026-08-29, the day the fixture has a bucket for. Local rather than
    /// UTC because the lookup uses the local calendar — which is what "today" means to the
    /// person reading the tab.
    private var onThatDay: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 29; components.hour = 12
        return Calendar.current.date(from: components)!
    }

    @Test("today's bucket is found by local calendar day")
    func tokensToday() throws {
        let usage = try usageFixture()
        #expect(CodexSnapshotMapper.tokensToday(from: usage, now: onThatDay) == 2_151_685)
    }

    @Test("a day with no bucket reports nothing rather than zero")
    func noBucketForToday() throws {
        let usage = try usageFixture()
        let laterDay = onThatDay.addingTimeInterval(40 * 86400)
        // Nil, not 0: the UI omits the line instead of claiming no usage.
        #expect(CodexSnapshotMapper.tokensToday(from: usage, now: laterDay) == nil)
    }

    @Test("token totals ride along in metadata without touching the windows")
    func metadata() throws {
        let limits = try decodeFixture("rate-limits-primary-only")
        let snapshot = CodexSnapshotMapper.snapshot(
            from: limits, tokenUsage: try usageFixture(), now: onThatDay
        )
        #expect(snapshot.metadata["tokensToday"] == "2151685")
        #expect(snapshot.metadata["tokensLifetime"] == "2723432")
        #expect(snapshot.windows.count == 1)   // unchanged by the extra read
    }

    @Test("a missing token read leaves the snapshot otherwise intact")
    func absentTokenUsage() throws {
        let limits = try decodeFixture("rate-limits-primary-only")
        let snapshot = CodexSnapshotMapper.snapshot(from: limits, tokenUsage: nil)
        #expect(snapshot.metadata["tokensToday"] == nil)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.plan == "go")
    }
}

@Suite("Provider states reach the boundary correctly")
struct ProviderStateContractTests {

    @Test("Codex produces a LIVE state with a timestamp")
    func codexIsLive() throws {
        let url = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/rate-limits-primary-only.json")
        let response = try JSONDecoder().decode(
            GetAccountRateLimitsResponse.self, from: Data(contentsOf: url)
        )
        let state = CodexSnapshotMapper.snapshot(from: response)

        #expect(state.status == .available)
        #expect(state.source == .live)      // a real read, and it says so
        #expect(state.lastUpdated != nil)
        #expect(state.failure == nil)
        #expect(state.hasFigures)
    }

    @Test("stubs produce UNSUPPORTED, never a fabricated reading")
    func stubsAreUnsupported() async throws {
        for provider: any UsageProvider in [ClaudeUsageProvider(), CursorUsageProvider()] {
            let state = try await provider.fetchUsage()
            #expect(state.status == .unsupported)
            #expect(state.source == .unavailable)
            #expect(state.hasFigures == false)
            #expect(state.windows.isEmpty)
            // A reason the UI can show, rather than an empty gap.
            #expect(state.failure?.isEmpty == false)
        }
    }

    @Test("a user-added tool is unsupported, not broken")
    func customIsUnsupported() async throws {
        let provider = CustomUsageProvider(
            providerType: ProviderType("antigravity"), displayName: "Antigravity"
        )
        let state = try await provider.fetchUsage()
        #expect(state.status == .unsupported)
        #expect(state.provider == ProviderType("antigravity"))
    }

    @Test(
        "provider errors map onto the right status",
        arguments: [
            (ProviderError.unsupported(reason: "x"), UsageStatus.unsupported),
            (.notInstalled, .unavailable),
            (.notRunning, .unavailable),
            (.authenticationRequired, .unavailable),
            (.network(detail: "x"), .unavailable),
            (.invalidResponse(detail: "x"), .error),
            (.unknown(detail: "x"), .error),
        ]
    )
    func errorStatuses(error: ProviderError, expected: UsageStatus) {
        // `.unsupported` must stay separate from the retryable failures: it is a statement
        // about the provider, not about this attempt.
        #expect(error.status == expected)
    }

    @Test("only unsupported is non-retryable")
    func retryability() {
        #expect(ProviderError.unsupported(reason: "x").status.isRetryable == false)
        for error: ProviderError in [.notRunning, .network(detail: "x"), .unknown(detail: "x")] {
            #expect(error.status.isRetryable)
        }
    }
}
