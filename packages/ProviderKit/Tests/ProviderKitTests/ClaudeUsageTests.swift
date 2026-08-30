import Testing
import Foundation
import SideNotchCore
@testable import ProviderKit

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name).json")
    return try Data(contentsOf: url)
}

@Suite("Claude usage response decoding")
struct ClaudeUsageDecodingTests {

    @Test("every documented window is recognised, in preferred order")
    func fullResponse() throws {
        let response = try ClaudeUsageDecoder.decode(fixture("claude-usage-full"))
        #expect(response.windows.count == 4)
        #expect(response.unknownKeys.isEmpty)

        let snapshot = ClaudeUsageMapper.snapshot(from: response, plan: "max")
        #expect(snapshot.status == .available)
        #expect(snapshot.source == .live)
        #expect(snapshot.plan == "max")

        // Order is the declared preference, not dictionary order, so the expanded card
        // does not reshuffle between refreshes.
        #expect(snapshot.windows.map(\.id) == ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"])
        #expect(snapshot.windows.map(\.label) == ["Session", "Weekly", "Weekly (Opus)", "Weekly (Sonnet)"])
    }

    @Test("percentages become fractions")
    func percentageConversion() throws {
        let response = try ClaudeUsageDecoder.decode(fixture("claude-usage-full"))
        let snapshot = ClaudeUsageMapper.snapshot(from: response, plan: nil)
        let session = try #require(snapshot.windows.first { $0.id == "five_hour" })
        let difference = abs((session.usedFraction ?? 0) - 0.734)
        #expect(difference < 0.0001)
    }

    @Test("the most-constrained window becomes the headline, not the first one")
    func headlineIsMostConstrained() throws {
        let response = try ClaudeUsageDecoder.decode(fixture("claude-usage-overage"))
        let snapshot = ClaudeUsageMapper.snapshot(from: response, plan: nil)
        let headline = try #require(snapshot.headlineWindow)
        #expect(headline.id == "five_hour")
    }

    @Test("a single-window reply is valid, not a partial failure")
    func sessionOnly() throws {
        let response = try ClaudeUsageDecoder.decode(fixture("claude-usage-session-only"))
        #expect(response.windows.count == 1)

        let snapshot = ClaudeUsageMapper.snapshot(from: response, plan: nil)
        #expect(snapshot.status == .available)
        #expect(snapshot.windows.count == 1)
        // Zero usage is a real reading for a fresh session, and must not read as "no data".
        #expect(snapshot.windows.first?.usedFraction == 0)
        #expect(snapshot.hasFigures)
    }

    @Test("fractional-second and epoch reset timestamps both parse")
    func timestampForms() throws {
        let fractional = try ClaudeUsageDecoder.decode(fixture("claude-usage-session-only"))
        #expect(fractional.windows["five_hour"]?.resetsAt != nil)

        let epoch = try ClaudeUsageDecoder.decode(fixture("claude-usage-overage"))
        let expected = Date(timeIntervalSince1970: 1_788_105_600)
        #expect(epoch.windows["five_hour"]?.resetsAt == expected)
    }

    @Test("a quoted percentage is still a percentage")
    func stringNumerics() throws {
        let response = try ClaudeUsageDecoder.decode(fixture("claude-usage-overage"))
        let utilization = try #require(response.windows["five_hour"]?.utilization)
        let difference = abs(utilization - 104.7)
        #expect(difference < 0.0001)
    }

    @Test("over-100% survives decoding but cannot drive a ring past full")
    func overageIsClampedAtTheBoundary() throws {
        let response = try ClaudeUsageDecoder.decode(fixture("claude-usage-overage"))
        // The DTO records what arrived...
        #expect((response.windows["five_hour"]?.utilization ?? 0) > 100)

        // ...and the window clamps it, so no view has to defend against a 1.047 turn.
        let snapshot = ClaudeUsageMapper.snapshot(from: response, plan: nil)
        let session = try #require(snapshot.windows.first { $0.id == "five_hour" })
        #expect(session.usedFraction == 1.0)
        #expect(session.level == .exhausted)
    }

    @Test("a renamed schema fails closed rather than reporting zero usage")
    func driftFailsClosed() throws {
        // This is the failure that matters most: if Anthropic renames the windows, the
        // wrong outcome is a confident 0% ring. It must throw instead.
        #expect(throws: ProviderError.self) {
            try ClaudeUsageDecoder.decode(fixture("claude-usage-drifted"))
        }
    }

    @Test("unrecognised keys are recorded without being treated as usage")
    func unknownKeysRecorded() throws {
        let response = try ClaudeUsageDecoder.decode(fixture("claude-usage-extra-keys"))
        #expect(response.windows.count == 1)
        #expect(response.unknownKeys == ["extra_usage", "rate_limit_tier", "seven_day_cowork"])

        let snapshot = ClaudeUsageMapper.snapshot(from: response, plan: nil)
        #expect(snapshot.metadata["schemaUnknownKeys"] != nil)
        // The drift note must not become a window.
        #expect(snapshot.windows.count == 1)
    }

    @Test("a non-object payload is rejected")
    func nonObjectPayload() {
        #expect(throws: ProviderError.self) {
            try ClaudeUsageDecoder.decode(Data("[1,2,3]".utf8))
        }
        #expect(throws: ProviderError.self) {
            try ClaudeUsageDecoder.decode(Data("not json".utf8))
        }
    }
}

@Suite("Claude credential handling")
struct ClaudeCredentialTests {

    @Test("a valid blob yields token, scopes, plan and expiry")
    func validCredential() throws {
        let credential = try ClaudeCredentialSource.parse(fixture("claude-credentials-valid"))
        #expect(credential.scopes == ["user:inference", "user:profile"])
        #expect(credential.subscriptionType == "max")
        #expect(credential.grantsUsageRead)
        #expect(credential.expiresAt != nil)
        #expect(!credential.accessToken.isEmpty)
    }

    @Test("a token without user:profile cannot read usage")
    func inferenceOnlyScope() throws {
        let credential = try ClaudeCredentialSource.parse(fixture("claude-credentials-inference-only"))
        // Structural, not transient: re-signing in with the same scope set changes nothing.
        #expect(!credential.grantsUsageRead)
    }

    @Test("an MCP-only store reads as signed out, not as corrupt")
    func mcpOnlyStore() {
        #expect(throws: ProviderError.authenticationRequired) {
            try ClaudeCredentialSource.parse(fixture("claude-credentials-mcp-only"))
        }
    }

    @Test("a malformed store is rejected")
    func malformedStore() {
        #expect(throws: ProviderError.self) {
            try ClaudeCredentialSource.parse(Data("{".utf8))
        }
    }

    static let expiryCases: [(offset: TimeInterval, expired: Bool)] = [
        (3600, false),    // an hour of life left
        (120, false),     // outside the 60s leeway
        (30, true),       // inside the leeway: treat as expired
        (-60, true),      // already gone
    ]

    @Test("expiry honours a leeway so a token cannot die mid-flight", arguments: expiryCases)
    func expiryLeeway(testCase: (offset: TimeInterval, expired: Bool)) {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let credential = ClaudeOAuthCredential(
            accessToken: Secret("x"),
            expiresAt: now.addingTimeInterval(testCase.offset),
            scopes: ["user:profile"],
            subscriptionType: nil
        )
        #expect(credential.isExpired(now: now) == testCase.expired)
    }

    // MARK: Choosing between duplicate keychain items

    private static func credential(
        scopes: [String] = ["user:profile"], expiresIn offset: TimeInterval?
    ) -> ClaudeOAuthCredential {
        ClaudeOAuthCredential(
            accessToken: Secret("x"),
            expiresAt: offset.map { Date(timeIntervalSince1970: 1_788_000_000 + $0) },
            scopes: scopes,
            subscriptionType: nil
        )
    }

    @Test("the freshest credential wins when the store holds several")
    func picksFreshest() throws {
        // Signing out and back in leaves a superseded item beside the live one, and the
        // keychain has no notion of "current" — so picking blind means intermittently
        // authenticating with a dead token.
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let stale = Self.credential(expiresIn: -10_000)
        let fresh = Self.credential(expiresIn: 10_000)
        let fresher = Self.credential(expiresIn: 50_000)

        let best = try #require(ClaudeCredentialSource.best(of: [stale, fresher, fresh], now: now))
        #expect(best.expiresAt == fresher.expiresAt)
    }

    @Test("usable scope outranks freshness")
    func scopeBeatsFreshness() throws {
        // A newer token that cannot read usage is worth less than an older one that can.
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let freshButUseless = Self.credential(scopes: ["user:inference"], expiresIn: 90_000)
        let olderButUsable = Self.credential(scopes: ["user:profile"], expiresIn: 10_000)

        let best = try #require(
            ClaudeCredentialSource.best(of: [freshButUseless, olderButUsable], now: now)
        )
        #expect(best.grantsUsageRead)
    }

    @Test("an unknown expiry outranks a known-lapsed one")
    func unknownBeatsLapsed() throws {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let lapsed = Self.credential(expiresIn: -10_000)
        let unknown = Self.credential(expiresIn: nil)

        let best = try #require(ClaudeCredentialSource.best(of: [lapsed, unknown], now: now))
        #expect(best.expiresAt == nil)
    }

    @Test("no candidates yields nothing rather than a default")
    func noCandidates() {
        #expect(ClaudeCredentialSource.best(of: []) == nil)
    }

    @Test("keychain payloads are extracted from every shape the API returns")
    func payloadShapes() {
        let bytes = Data("blob".utf8)
        let key = kSecValueData as String

        // macOS returns an array of attribute dictionaries for kSecMatchLimitAll...
        #expect(ClaudeCredentialSource.payloads(from: [[key: bytes]] as CFArray)?.count == 1)
        // ...a single dictionary, or bare data, in the other forms.
        #expect(ClaudeCredentialSource.payloads(from: [key: bytes] as CFDictionary)?.count == 1)
        #expect(ClaudeCredentialSource.payloads(from: bytes as CFData)?.count == 1)
        #expect(ClaudeCredentialSource.payloads(from: "nonsense" as CFString) == nil)
    }

    @Test("an absent expiry is not treated as expired")
    func absentExpiry() {
        let credential = ClaudeOAuthCredential(
            accessToken: Secret("x"), expiresAt: nil,
            scopes: ["user:profile"], subscriptionType: nil
        )
        #expect(!credential.isExpired())
    }
}

@Suite("Secret redaction")
struct SecretTests {

    @Test("a secret cannot be printed by any of the reflexive routes")
    func redactsEveryDescription() {
        let secret = Secret("super-sensitive-value")
        #expect(secret.description == "<redacted>")
        #expect(secret.debugDescription == "<redacted>")
        #expect(String(describing: secret) == "<redacted>")
        #expect("\(secret)" == "<redacted>")
        #expect(!String(reflecting: secret).contains("super-sensitive"))
    }

    @Test("a secret refuses to be encoded, so it cannot reach disk")
    func refusesEncoding() {
        #expect(throws: (any Error).self) {
            try JSONEncoder().encode(Secret("super-sensitive-value"))
        }
    }

    @Test("reveal is the only way out, and it round-trips exactly")
    func revealRoundTrips() {
        #expect(Secret("abc-123").reveal() == "abc-123")
        #expect(Secret("").isEmpty)
        #expect(Secret("abcd").count == 4)
    }
}

@Suite("Endpoint rate limiting")
struct EndpointRateLimiterTests {

    @Test("the first call is allowed and the immediate second is not")
    func minimumInterval() async {
        let limiter = EndpointRateLimiter(minimumInterval: 180)
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        #expect(await limiter.claim(now: start) == nil)

        let tooSoon = await limiter.claim(now: start.addingTimeInterval(30))
        guard case .tooSoon = tooSoon else {
            Issue.record("expected a tooSoon refusal, got \(String(describing: tooSoon))")
            return
        }

        // Once the floor has passed, the next call goes through.
        #expect(await limiter.claim(now: start.addingTimeInterval(181)) == nil)
    }

    @Test("a 429 blocks for the backoff period, and the ladder doubles")
    func backoffLadder() async {
        let limiter = EndpointRateLimiter(
            minimumInterval: 10, initialBackoff: 300, maximumBackoff: 1800
        )
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        #expect(await limiter.claim(now: start) == nil)
        await limiter.recordRateLimited(now: start)

        // Still inside the first 300s penalty.
        let blocked = await limiter.claim(now: start.addingTimeInterval(299))
        guard case .backingOff = blocked else {
            Issue.record("expected backingOff, got \(String(describing: blocked))")
            return
        }

        // Past it, the call is allowed again.
        let after = start.addingTimeInterval(301)
        #expect(await limiter.claim(now: after) == nil)

        // A second 429 doubles the penalty to 600s.
        await limiter.recordRateLimited(now: after)
        #expect(await limiter.backingOff(now: after.addingTimeInterval(599)))
        #expect(!(await limiter.backingOff(now: after.addingTimeInterval(601))))
    }

    @Test("the ladder is capped so it cannot grow without bound")
    func backoffCeiling() async {
        let limiter = EndpointRateLimiter(
            minimumInterval: 0, initialBackoff: 300, maximumBackoff: 1800
        )
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        // Six consecutive 429s would reach 9600s without a ceiling.
        for _ in 0..<6 {
            await limiter.recordRateLimited(now: start)
        }
        // The penalty currently in force must not exceed the ceiling.
        #expect(!(await limiter.backingOff(now: start.addingTimeInterval(1801))))
    }

    @Test("a Retry-After header wins over the ladder")
    func honoursRetryAfter() async {
        let limiter = EndpointRateLimiter(initialBackoff: 300)
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        await limiter.recordRateLimited(retryAfter: 45, now: start)
        #expect(await limiter.backingOff(now: start.addingTimeInterval(44)))
        #expect(!(await limiter.backingOff(now: start.addingTimeInterval(46))))
    }

    @Test("success clears the penalty and resets the ladder")
    func successResets() async {
        let limiter = EndpointRateLimiter(minimumInterval: 0, initialBackoff: 300)
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        await limiter.recordRateLimited(now: start)
        #expect(await limiter.backingOff(now: start))

        await limiter.recordSuccess()
        #expect(!(await limiter.backingOff(now: start)))

        // The ladder is back to its first rung, not still doubled.
        await limiter.recordRateLimited(now: start)
        #expect(!(await limiter.backingOff(now: start.addingTimeInterval(301))))
    }

    @Test("a transport failure does not escalate the ladder")
    func transportFailureDoesNotEscalate() async {
        // An hour offline must not leave us at the 30-minute ceiling once the network
        // returns — the provider never refused us, the network did.
        let limiter = EndpointRateLimiter(minimumInterval: 0, initialBackoff: 300)
        let start = Date(timeIntervalSince1970: 1_788_000_000)

        for _ in 0..<5 {
            await limiter.recordTransportFailure()
        }
        #expect(!(await limiter.backingOff(now: start)))
        #expect(await limiter.claim(now: start) == nil)
    }
}
