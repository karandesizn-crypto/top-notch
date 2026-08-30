import Testing
import Foundation
import SideNotchCore
@testable import ProviderKit

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name).json")
    return try Data(contentsOf: url)
}

@Suite("Cursor usage response decoding")
struct CursorUsageDecodingTests {

    @Test("metered and unmetered buckets are both recognised")
    func meteredResponse() throws {
        let response = try CursorUsageDecoder.decode(fixture("cursor-usage-metered"))
        #expect(response.models.count == 2)
        #expect(response.unknownKeys.isEmpty)
        #expect(response.startOfMonth != nil)
    }

    @Test("a metered bucket yields a fraction")
    func meteredFraction() throws {
        let response = try CursorUsageDecoder.decode(fixture("cursor-usage-metered"))
        let premium = try #require(response.models["gpt-4"])
        #expect(premium.numRequests == 312)
        #expect(premium.maxRequestUsage == 500)
        let difference = abs((premium.usedFraction ?? 0) - 0.624)
        #expect(difference < 0.0001)
    }

    @Test("an unmetered bucket has no fraction rather than a guessed one")
    func unmeteredHasNoFraction() throws {
        // This is the fabrication guard. A null ceiling means no percentage exists; the
        // temptation is to substitute a plausible denominator, which would invent a number
        // the provider never reported.
        let response = try CursorUsageDecoder.decode(fixture("cursor-usage-metered"))
        let basic = try #require(response.models["gpt-3.5-turbo"])
        #expect(basic.maxRequestUsage == nil)
        #expect(basic.usedFraction == nil)

        let snapshot = CursorUsageMapper.snapshot(from: response)
        let window = try #require(snapshot.windows.first { $0.id == "gpt-3.5-turbo" })
        #expect(window.usedFraction == nil)
        #expect(window.level == nil)
    }

    @Test("the reset lands a calendar month after the billing start, not 30 days")
    func resetIsCalendarMonth() throws {
        let response = try CursorUsageDecoder.decode(fixture("cursor-usage-metered"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let snapshot = CursorUsageMapper.snapshot(from: response, calendar: calendar)
        let window = try #require(snapshot.windows.first { $0.id == "gpt-4" })
        let reset = try #require(window.resetDate)

        // August has 31 days, so a naive +30d would land on the 31st.
        let components = calendar.dateComponents([.year, .month, .day], from: reset)
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 1)
    }

    @Test("request counts reach metadata for the expanded card")
    func metadataCarriesCounts() throws {
        let response = try CursorUsageDecoder.decode(fixture("cursor-usage-metered"))
        let snapshot = CursorUsageMapper.snapshot(from: response)
        #expect(snapshot.metadata["gpt-4.used"] == "312")
        #expect(snapshot.metadata["gpt-4.limit"] == "500")
        // The unmetered bucket has a count but no limit to report.
        #expect(snapshot.metadata["gpt-3.5-turbo.used"] == "47")
        #expect(snapshot.metadata["gpt-3.5-turbo.limit"] == nil)
    }

    @Test("an account with no metered quota is explained, not silently blank")
    func unmeteredAccountIsExplained() throws {
        // Verified against a live account: the endpoint answers 200 with every ceiling
        // null when the account is on usage-based pricing. The read worked; there is
        // simply no percentage to show, and the UI needs to be able to say which.
        let response = try CursorUsageDecoder.decode(fixture("cursor-usage-unmetered"))
        #expect(response.models["gpt-4"]?.maxRequestUsage == nil)

        let snapshot = CursorUsageMapper.snapshot(from: response)
        #expect(snapshot.status == .unavailable)
        #expect(snapshot.failure == "No metered quota")
        #expect(snapshot.hasFigures == false)
        // Retryable: the account could gain a metered pool later.
        #expect(snapshot.status.isRetryable)
    }

    @Test("a renamed schema fails closed rather than reporting zero usage")
    func driftFailsClosed() {
        #expect(throws: ProviderError.self) {
            try CursorUsageDecoder.decode(fixture("cursor-usage-drifted"))
        }
    }

    @Test("a non-object payload is rejected")
    func nonObjectPayload() {
        #expect(throws: ProviderError.self) {
            try CursorUsageDecoder.decode(Data("[]".utf8))
        }
    }

    @Test("a live snapshot is marked live, with figures")
    func snapshotProvenance() throws {
        let response = try CursorUsageDecoder.decode(fixture("cursor-usage-metered"))
        let snapshot = CursorUsageMapper.snapshot(from: response)
        #expect(snapshot.provider == .cursor)
        #expect(snapshot.status == .available)
        #expect(snapshot.source == .live)
        #expect(snapshot.hasFigures)
    }
}

@Suite("Cursor credential handling")
struct CursorCredentialTests {

    /// A structurally valid JWT whose payload is `{"sub":"fixture","exp":4102444800}`.
    /// The signature segment is a placeholder — nothing here verifies signatures, and
    /// nothing here is a real token.
    static let fixtureJWT = "eyJhbGciOiJIUzI1NiJ9"
        + ".eyJzdWIiOiJmaXh0dXJlIiwiZXhwIjo0MTAyNDQ0ODAwfQ"
        + ".FIXTURE-SIGNATURE-NOT-VERIFIED"

    @Test("the exp claim is read without verifying the signature")
    func readsExpiry() {
        let expiry = CursorCredentialSource.expiry(ofJWT: Self.fixtureJWT)
        #expect(expiry == Date(timeIntervalSince1970: 4_102_444_800))
    }

    @Test("base64url padding is restored before decoding")
    func base64URLPadding() {
        // Three-character remainder needs one '=' to decode.
        let decoded = CursorCredentialSource.base64URLDecode("eyJhIjoxfQ")
        #expect(decoded != nil)
    }

    static let malformedTokens = [
        "",
        "not-a-jwt",
        "only.two",
        "aaa.!!!not-base64!!!.ccc",
    ]

    @Test("a malformed token reports unknown expiry, never a bogus date", arguments: malformedTokens)
    func malformedTokenHasNoExpiry(token: String) {
        // Unknown expiry is safe: the caller treats nil as "worth trying", and the request
        // either succeeds or 401s into an honest unavailable.
        #expect(CursorCredentialSource.expiry(ofJWT: token) == nil)
    }

    @Test("a credential with unknown expiry is not treated as expired")
    func unknownExpiryIsUsable() {
        let credential = CursorCredential(accessToken: Secret("x"), expiresAt: nil)
        #expect(!credential.isExpired())
    }

    @Test("expiry honours the leeway")
    func expiryLeeway() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        let expiring = CursorCredential(
            accessToken: Secret("x"), expiresAt: now.addingTimeInterval(30)
        )
        #expect(expiring.isExpired(now: now))

        let healthy = CursorCredential(
            accessToken: Secret("x"), expiresAt: now.addingTimeInterval(3600)
        )
        #expect(!healthy.isExpired(now: now))
    }

    @Test("a missing state database reads as not installed")
    func missingDatabase() {
        let source = CursorCredentialSource(
            databaseURL: URL(fileURLWithPath: "/nonexistent/state.vscdb")
        )
        #expect(throws: ProviderError.notInstalled) {
            try source.read()
        }
    }
}
