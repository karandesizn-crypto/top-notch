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
        #expect(window.state == .normal)
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
        #expect(snapshot.availability == .available)
        #expect(snapshot.plan == nil)
        #expect(snapshot.overallState == .unavailable)
    }

    @Test("a window with no duration falls back to a generic label rather than guessing")
    func missingDuration() throws {
        let snapshot = CodexSnapshotMapper.snapshot(from: try decodeFixture("rate-limits-spend-control"))
        let primary = try #require(snapshot.windows.first { $0.id == "primary" })
        #expect(primary.label == "Current window")
        #expect(primary.duration == nil)
        #expect(primary.resetDate == nil)
        #expect(primary.state == .critical)         // 96%
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

@Suite("Usage state thresholds")
struct UsageStateTests {
    // Precomputed: the compiler cannot type-check arithmetic inside `arguments`.
    static let boundaryCases: [(Double, UsageState)] = [
        (0.0, .normal), (0.21, .normal), (0.49, .normal),
        (0.50, .warning), (0.52, .warning), (0.69, .warning),
        (0.70, .critical), (0.73, .critical), (0.99, .critical),
        (1.0, .exhausted), (1.4, .exhausted),
    ]

    /// The boundaries encode the reference design: 21% calm, 52% noticed, 73% hot.
    @Test("state boundaries", arguments: UsageStateTests.boundaryCases)
    func boundaries(fraction: Double, expected: UsageState) {
        #expect(UsageStateEvaluator.state(forUsedFraction: fraction) == expected)
    }

    @Test("an absent measurement is unavailable, never normal")
    func absentIsUnavailable() {
        #expect(UsageStateEvaluator.state(forUsedFraction: nil) == .unavailable)
    }

    @Test("fractions are clamped so a ring cannot exceed a full turn")
    func clamping() {
        #expect(UsageWindow.normalize(1.4) == 1)
        #expect(UsageWindow.normalize(-0.2) == 0)
        #expect(UsageWindow.normalize(.nan) == 0)
        // Over-100% still reads as exhausted, and the ring stays full.
        let window = UsageWindow.fromPercentage(id: "p", label: "x", percent: 140)
        #expect(window.usedFraction == 1)
        #expect(window.state == .exhausted)
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
            await #expect(throws: ProviderError.self) { try await provider.fetchSnapshot() }
        }
    }

    @Test("mock failure surfaces through the protocol")
    func mockFailure() async throws {
        let cursor = try #require(MockUsageProvider.showcase().first { $0.id == .cursor })
        await #expect(throws: ProviderError.self) { try await cursor.fetchSnapshot() }
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
