import Testing
import Foundation
import SideNotchCore
@testable import ProviderKit

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name).json")
    return try Data(contentsOf: url)
}

@Suite("Claude provider behaviour")
struct ClaudeProviderBehaviourTests {

    @Test("a successful read produces live figures")
    func successProducesLiveFigures() async throws {
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("claude-usage-full"))),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .available)
        #expect(state.source == .live)
        #expect(state.provider == .claude)
        #expect(state.plan == "max")
        #expect(state.windows.count == 4)
        #expect(state.failure == nil)
    }

    @Test("the request carries the authorization, beta gate and user agent")
    func requestHeaders() async throws {
        let recorder = HeaderRecorder()
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("claude-usage-full")), recorder: recorder),
            limiter: unthrottled()
        )
        _ = try await provider.fetchUsage()

        let headers = await recorder.headers
        #expect(headers["Authorization"] == "Bearer FIXTURE-NOT-A-REAL-TOKEN")
        // The beta gate is what the endpoint requires; without it the call 404s.
        #expect(headers["anthropic-beta"] == "oauth-2025-04-20")
        // Identifying the client demonstrably affects how fast the endpoint starts refusing.
        #expect(headers["User-Agent"]?.contains("TopNotch") == true)

        let url = await recorder.url
        #expect(url?.host == "api.anthropic.com")
        #expect(url?.path == "/api/oauth/usage")
    }

    @Test("the token never reaches a user-facing field")
    func tokenNeverSurfaces() async throws {
        // Belt and braces around the Secret type: even on the success path, nothing the UI
        // can render may contain the credential.
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("claude-usage-full"))),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        let renderable = [state.failure, state.plan].compactMap { $0 }
            + state.metadata.values
            + state.windows.map(\.label)
        for value in renderable {
            #expect(!value.contains("FIXTURE-NOT-A-REAL-TOKEN"))
        }
    }

    @Test("a stored expiry in the past does not stop the attempt")
    func staleExpiryStillAttempts() async throws {
        // Regression test for a real failure. Gating on the stored expiry made the adapter
        // answer "Sign-in expired" forever without ever asking the endpoint, on a machine
        // where the keychain's `expiresAt` had lapsed but the login was fine. The stored
        // claim is advisory; the endpoint is the authority.
        let recorder = HeaderRecorder()
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(
                expiresAt: Date(timeIntervalSince1970: 1_000_000)  // long past
            ),
            http: StubHTTPClient(.success(try fixture("claude-usage-full")), recorder: recorder),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(await recorder.callCount == 1)
        // And when the endpoint accepts it, the figures are live despite the stale claim.
        #expect(state.status == .available)
        #expect(state.windows.count == 4)
    }

    @Test("a rejected stale token is worded as expired, a rejected live one is not")
    func rejectionWordingFollowsStoredExpiry() async throws {
        let stale = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(
                expiresAt: Date(timeIntervalSince1970: 1_000_000)
            ),
            http: StubHTTPClient(.unauthorized()),
            limiter: unthrottled()
        )
        #expect(try await stale.fetchUsage().failure == "Sign-in expired")

        let live = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.unauthorized()),
            limiter: unthrottled()
        )
        #expect(try await live.fetchUsage().failure == "Sign-in required")
    }

    @Test("provider-controlled error text never reaches a user-facing field")
    func endpointTextStaysOutOfTheUI() async throws {
        // The endpoint's error body is text we do not control, and the rail renders
        // `failure` directly. Capturing it for diagnostics is useful; letting it through to
        // the UI would hand a remote party the copy in a 185pt strip. It goes to metadata,
        // which the UI does not render, and never to `failure`.
        let hostile = "javascript:alert(1) — a very long remote-controlled string that would wreck the layout"
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.unauthorized(detail: hostile)),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.failure == "Sign-in required")
        #expect(state.failure?.contains("javascript") == false)
        // Captured, but only where diagnostics look.
        #expect(state.metadata["endpointDetail"] == hostile)
    }

    @Test("an overlong transport reason is clamped to something the rail can draw")
    func transportReasonIsClamped() async throws {
        // The transport path is the only one whose detail reaches user-facing copy. It is
        // ours by construction today; the clamp makes that safe by type rather than by
        // convention.
        let sprawling = String(repeating: "connection failure ", count: 20)
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.transport(detail: sprawling)),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        let failure = try #require(state.failure)
        #expect(failure.count <= 32)
        #expect(failure.hasSuffix("…"))
    }

    @Test("a short transport reason passes through unchanged")
    func shortTransportReasonSurvives() async throws {
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.transport(detail: "Offline")),
            limiter: unthrottled()
        )
        #expect(try await provider.fetchUsage().failure == "Offline")
    }

    @Test("a rate-limit body is captured for diagnostics but not rendered")
    func rateLimitDetailCaptured() async throws {
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(
                .rateLimited(retryAfter: nil, detail: "rate_limit_error: Rate limited.")
            ),
            limiter: EndpointRateLimiter(minimumInterval: 0, initialBackoff: 300)
        )
        let state = try await provider.fetchUsage()

        #expect(state.failure == "Rate limited")
        #expect(state.metadata["endpointDetail"]?.contains("rate_limit_error") == true)
    }

    @Test("a rejection records which store the credential came from")
    func rejectionRecordsOrigin() async throws {
        // Without this, the same 401 cannot be told apart from "your login lapsed" and
        // "we read a superseded credential file", which need different fixes.
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.unauthorized()),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()
        #expect(state.metadata["credentialSource"] != nil)
        #expect(state.metadata["storedExpiryPassed"] == "false")
    }

    @Test("a token without the usage scope is unsupported, not merely unavailable")
    func missingScopeIsStructural() async throws {
        let recorder = HeaderRecorder()
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(scopes: ["user:inference"]),
            http: StubHTTPClient(.success(Data()), recorder: recorder),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        // Retrying cannot fix a scope that was never granted, so this must not be marked
        // retryable — otherwise the scheduler polls forever against a guaranteed 403.
        #expect(state.status == .unsupported)
        #expect(state.status.isRetryable == false)
        #expect(await recorder.callCount == 0)
    }

    @Test("a rate-limit refusal costs no request at all")
    func throttledReadMakesNoRequest() async throws {
        let recorder = HeaderRecorder()
        let limiter = EndpointRateLimiter(minimumInterval: 180)
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("claude-usage-full")), recorder: recorder),
            limiter: limiter
        )

        let first = try await provider.fetchUsage()
        #expect(first.status == .available)
        #expect(await recorder.callCount == 1)

        // The second read arrives inside the floor and must be refused locally.
        let second = try await provider.fetchUsage()
        #expect(second.status == .unavailable)
        #expect(second.status.isRetryable)   // so the manager keeps the previous figures
        #expect(await recorder.callCount == 1)
    }

    @Test("a 429 arms the backoff rather than erroring")
    func rateLimitedResponseArmsBackoff() async throws {
        let limiter = EndpointRateLimiter(minimumInterval: 0, initialBackoff: 300)
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.rateLimited(retryAfter: nil, detail: nil)),
            limiter: limiter
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .unavailable)
        #expect(state.failure == "Rate limited")
        #expect(await limiter.backingOff())
    }

    @Test("a 401 does not trigger a refresh, it reports and waits")
    func unauthorizedDoesNotRefresh() async throws {
        // The account-safety rule: a rejected token is Claude Code's to renew. Attempting
        // it here is what revokes the user's token family and signs them out of the CLI.
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.unauthorized()),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .unavailable)
        #expect(state.hasFigures == false)
        #expect(state.failure == "Sign-in required")
    }

    @Test("a server error degrades to unavailable, never to figures")
    func serverErrorDegrades() async throws {
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.http(status: 503, detail: nil)),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .unavailable)
        #expect(state.windows.isEmpty)
    }

    @Test("being offline degrades to unavailable")
    func offlineDegrades() async throws {
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.transport(detail: "Offline")),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .unavailable)
        #expect(state.failure == "Offline")
        #expect(state.windows.isEmpty)
    }

    @Test("a drifted schema surfaces as an error, never as a zeroed ring")
    func driftSurfacesAsError() async throws {
        let provider = ClaudeUsageProvider(
            credentials: StubClaudeCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("claude-usage-drifted"))),
            limiter: unthrottled()
        )
        // Propagated rather than swallowed: the manager records it as `.error`, which is
        // visibly different from "you have used nothing".
        await #expect(throws: ProviderError.self) {
            try await provider.fetchUsage()
        }
    }
}

@Suite("Cursor provider behaviour")
struct CursorProviderBehaviourTests {

    @Test("a successful read produces live figures")
    func successProducesLiveFigures() async throws {
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("cursor-usage-metered"))),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .available)
        #expect(state.source == .live)
        #expect(state.provider == .cursor)
        #expect(state.windows.count == 2)
    }

    @Test("the request carries a bearer token and no cookie")
    func requestHeaders() async throws {
        let recorder = HeaderRecorder()
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("cursor-usage-metered")), recorder: recorder),
            limiter: unthrottled()
        )
        _ = try await provider.fetchUsage()

        let headers = await recorder.headers
        #expect(headers["Authorization"] == "Bearer FIXTURE-NOT-A-REAL-TOKEN")
        // The deliberate boundary: this adapter authenticates as the editor does, and
        // never reconstructs or replays a browser session cookie.
        #expect(headers["Cookie"] == nil)
    }

    @Test("an expired token is reported without spending a request")
    func expiredTokenSkipsRequest() async throws {
        let recorder = HeaderRecorder()
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(
                expiresAt: Date(timeIntervalSince1970: 1_000_000)
            ),
            http: StubHTTPClient(.success(Data()), recorder: recorder),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .unavailable)
        #expect(await recorder.callCount == 0)
    }

    @Test("a missing Cursor install reads as unavailable with a reason")
    func notInstalled() async throws {
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.failing(.notInstalled),
            http: StubHTTPClient(.success(Data())),
            limiter: unthrottled()
        )
        let state = try await provider.fetchUsage()

        #expect(state.status == .unavailable)
        #expect(state.failure == "Cursor not installed")
    }

    @Test("a drifted schema surfaces as an error, never as a zeroed ring")
    func driftSurfacesAsError() async throws {
        let provider = CursorUsageProvider(
            credentials: StubCursorCredentials.valid(),
            http: StubHTTPClient(.success(try fixture("cursor-usage-drifted"))),
            limiter: unthrottled()
        )
        await #expect(throws: ProviderError.self) {
            try await provider.fetchUsage()
        }
    }
}
