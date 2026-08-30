import Testing
import Foundation
import SideNotchCore
@testable import ProviderKit

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name).json")
    return try Data(contentsOf: url)
}

@Suite("Cursor dashboard (Connect RPC)")
struct CursorDashboardTests {

    @Test("a metered period yields a real percentage")
    func meteredPeriod() throws {
        // The whole reason this endpoint was adopted: the legacy one returns all-null
        // ceilings on a modern account, so it can produce no percentage at all.
        let dto = try CursorPeriodUsageDecoder.decode(fixture("cursor-dashboard-metered"))
        #expect(dto.isMetered)
        #expect(dto.limitCents == 2000)
        #expect(dto.remainingCents == 530)

        let snapshot = CursorPeriodUsageMapper.snapshot(from: dto)
        #expect(snapshot.status == .available)
        #expect(snapshot.source == .live)
        #expect(snapshot.windows.count == 1)

        let window = try #require(snapshot.windows.first)
        #expect(window.id == "billingPeriod")
        let difference = abs((window.usedFraction ?? 0) - 0.735)
        #expect(difference < 0.0001)
    }

    @Test("the billing cycle end becomes the reset, parsed from epoch milliseconds")
    func billingCycleParsing() throws {
        // The response sends timestamps as numeric *strings* in milliseconds, in the same
        // payload where percentages are numbers. Getting the unit wrong here would put the
        // reset in 1970 and read as permanently overdue.
        let dto = try CursorPeriodUsageDecoder.decode(fixture("cursor-dashboard-metered"))
        let expected = Date(timeIntervalSince1970: 1_790_669_301)
        #expect(dto.billingCycleEnd == expected)

        let snapshot = CursorPeriodUsageMapper.snapshot(from: dto)
        #expect(snapshot.windows.first?.resetDate == expected)
        // Duration spans the cycle, so the reset phrasing can name a day rather than count
        // hours across a month.
        let duration = try #require(snapshot.windows.first?.duration)
        #expect(duration > 2_000_000)
    }

    @Test("thresholds apply, so 73.5% reads as a warning rather than normal")
    func levelFollowsThresholds() throws {
        let dto = try CursorPeriodUsageDecoder.decode(fixture("cursor-dashboard-metered"))
        let snapshot = CursorPeriodUsageMapper.snapshot(from: dto)
        // Shared UsageThresholds, not a private ramp — the same rule every provider uses.
        #expect(snapshot.windows.first?.level == .critical)
    }

    @Test("sub-metrics and allowance reach metadata without being formatted as currency")
    func metadataCarriesDetail() throws {
        let dto = try CursorPeriodUsageDecoder.decode(fixture("cursor-dashboard-metered"))
        let snapshot = CursorPeriodUsageMapper.snapshot(from: dto)
        #expect(snapshot.metadata["includedLimitCents"] == "2000")
        #expect(snapshot.metadata["remainingCents"] == "530")
        #expect(snapshot.metadata["outcome"] == "metered")
        #expect(snapshot.metadata["source"] == "dashboard")
        // The response never names a currency; inventing a symbol would be inventing
        // information.
        for value in snapshot.metadata.values {
            #expect(!value.contains("$"))
        }
    }

    @Test("a zero allowance is no metered quota, not a zero-percent ring")
    func zeroAllowanceIsUnmetered() throws {
        // A percentage with no allowance behind it describes nothing. Drawing a confident
        // 0% ring would claim the user has an untouched quota they do not have.
        let dto = try CursorPeriodUsageDecoder.decode(fixture("cursor-dashboard-unmetered"))
        #expect(!dto.isMetered)

        let snapshot = CursorPeriodUsageMapper.snapshot(from: dto)
        #expect(snapshot.status == .unavailable)
        #expect(snapshot.failure == "No metered quota")
        #expect(snapshot.metadata["readSucceeded"] == "true")
        #expect(snapshot.windows.isEmpty)
    }

    @Test("a renamed schema fails closed")
    func driftFailsClosed() {
        #expect(throws: ProviderError.self) {
            try CursorPeriodUsageDecoder.decode(fixture("cursor-dashboard-drifted"))
        }
    }

    @Test("unrecognised keys are recorded but never become usage")
    func unknownKeysRecorded() throws {
        let data = try fixture("cursor-dashboard-extra-keys")
        let unknown = CursorPeriodUsageDecoder.unknownKeys(in: data)
        #expect(unknown == ["anotherNewThing", "brandNewField"])

        let dto = try CursorPeriodUsageDecoder.decode(data)
        let snapshot = CursorPeriodUsageMapper.snapshot(from: dto, unknownKeys: unknown)
        #expect(snapshot.metadata["schemaUnknownKeys"] == "anotherNewThing,brandNewField")
        #expect(snapshot.windows.count == 1)
    }

    @Test("a non-object payload is rejected")
    func nonObjectPayload() {
        #expect(throws: ProviderError.self) {
            try CursorPeriodUsageDecoder.decode(Data("[]".utf8))
        }
    }
}

@Suite("Cursor endpoint preference")
struct CursorEndpointPreferenceTests {

    @Test("the dashboard is tried first, and the legacy endpoint is not called when it works")
    func dashboardPreferred() async throws {
        let recorder = HeaderRecorder()
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(),
            http: StubHTTPClient(
                .success(try fixture("cursor-usage-metered")),
                post: .success(try fixture("cursor-dashboard-metered")),
                recorder: recorder
            ),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .available)
        #expect(state.metadata["source"] == "dashboard")
        // One request, not two: the fallback must not fire when the primary succeeded.
        #expect(await recorder.methods == ["POST"])
    }

    @Test("the Connect protocol header is sent, and no cookie ever is")
    func connectHeaders() async throws {
        let recorder = HeaderRecorder()
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(),
            http: StubHTTPClient(
                .http(status: 500, detail: nil),
                post: .success(try fixture("cursor-dashboard-metered")),
                recorder: recorder
            ),
            limiter: unthrottled()
        )
        _ = try await provider.fetchUsage()

        let headers = try #require(await recorder.headers(forFirst: "POST"))
        // Without this the service rejects the call outright.
        #expect(headers["Connect-Protocol-Version"] == "1")
        #expect(headers["Authorization"] == "Bearer FIXTURE-NOT-A-REAL-TOKEN")
        // The boundary this adapter refuses to cross.
        #expect(headers["Cookie"] == nil)
    }

    @Test("a dashboard failure falls back to the legacy request pool")
    func fallsBackToLegacy() async throws {
        // Older accounts are still governed by a request quota, and that endpoint is the
        // right answer for them.
        let recorder = HeaderRecorder()
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(),
            http: StubHTTPClient(
                .success(try fixture("cursor-usage-metered")),
                post: .http(status: 404, detail: nil),
                recorder: recorder
            ),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(await recorder.methods == ["POST", "GET"])
        #expect(state.status == .available)
        #expect(state.metadata["source"] == nil)   // legacy path, not dashboard
        #expect(state.windows.contains { $0.id == "gpt-4" })
    }

    @Test("when both endpoints fail, no figures are invented")
    func bothFail() async throws {
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(),
            http: StubHTTPClient(.unauthorized(), post: .http(status: 500, detail: nil)),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.hasFigures == false)
        #expect(state.windows.isEmpty)
        #expect(state.failure?.isEmpty == false)
    }
}
