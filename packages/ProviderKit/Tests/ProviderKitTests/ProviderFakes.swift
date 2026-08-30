import Foundation
@testable import ProviderKit

/// Test doubles for the two seams that would otherwise reach outside the process.
///
/// Every provider test in this target runs through these. Nothing in the suite may open a
/// socket or touch the real keychain: a unit test that depends on the user being signed in
/// to Claude Code fails on a colleague's machine and in CI, and one that calls the live
/// usage endpoint burns the rate limit the product depends on.

/// Returns a canned HTTP outcome without a network call.
///
/// GET and POST are answered separately because Cursor now tries its Connect RPC dashboard
/// endpoint (POST) before falling back to the legacy request-pool endpoint (GET). A stub
/// that answered both identically would feed a legacy payload to the dashboard decoder and
/// fail for reasons that have nothing to do with the test.
///
/// POST therefore defaults to a 404, which is what makes an unqualified
/// `StubHTTPClient(.success(...))` mean "the legacy path answers this" — the shape most of
/// these tests want.
struct StubHTTPClient: UsageHTTPPerforming {
    let getOutcome: HTTPOutcome
    let postOutcome: HTTPOutcome
    /// Records the requests so tests can assert on headers, method and count.
    let recorder: HeaderRecorder?

    init(
        _ getOutcome: HTTPOutcome,
        post postOutcome: HTTPOutcome = .http(status: 404, detail: nil),
        recorder: HeaderRecorder? = nil
    ) {
        self.getOutcome = getOutcome
        self.postOutcome = postOutcome
        self.recorder = recorder
    }

    func get(_ url: URL, headers: [String: String]) async -> HTTPOutcome {
        await recorder?.record(method: "GET", url: url, headers: headers)
        return getOutcome
    }

    func post(_ url: URL, headers: [String: String], body: Data) async -> HTTPOutcome {
        await recorder?.record(method: "POST", url: url, headers: headers)
        return postOutcome
    }
}

/// Captures what a provider actually put on the wire.
actor HeaderRecorder {
    private(set) var url: URL?
    private(set) var headers: [String: String] = [:]
    private(set) var callCount = 0
    private(set) var methods: [String] = []
    /// Every request, so a test can assert on the one it cares about rather than the last.
    private(set) var requests: [(method: String, url: URL, headers: [String: String])] = []

    func record(method: String, url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
        methods.append(method)
        requests.append((method, url, headers))
        callCount += 1
    }

    /// Headers of the first request made with `method`.
    func headers(forFirst method: String) -> [String: String]? {
        requests.first { $0.method == method }?.headers
    }
}

/// Supplies a Claude credential, or the failure of your choice.
struct StubClaudeCredentials: ClaudeCredentialReading {
    let result: Result<ClaudeOAuthCredential, ProviderError>

    static func valid(
        scopes: [String] = ["user:inference", "user:profile"],
        expiresAt: Date? = Date(timeIntervalSince1970: 4_102_444_800),
        plan: String? = "max"
    ) -> StubClaudeCredentials {
        StubClaudeCredentials(result: .success(
            ClaudeOAuthCredential(
                accessToken: Secret("FIXTURE-NOT-A-REAL-TOKEN"),
                expiresAt: expiresAt,
                scopes: scopes,
                subscriptionType: plan
            )
        ))
    }

    static func failing(_ error: ProviderError) -> StubClaudeCredentials {
        StubClaudeCredentials(result: .failure(error))
    }

    func read() throws -> ClaudeOAuthCredential {
        try result.get()
    }
}

/// Supplies a Cursor credential, or the failure of your choice.
struct StubCursorCredentials: CursorCredentialReading {
    let result: Result<CursorCredential, ProviderError>

    static func valid(
        expiresAt: Date? = Date(timeIntervalSince1970: 4_102_444_800)
    ) -> StubCursorCredentials {
        StubCursorCredentials(result: .success(
            CursorCredential(
                accessToken: Secret("FIXTURE-NOT-A-REAL-TOKEN"),
                expiresAt: expiresAt
            )
        ))
    }

    static func failing(_ error: ProviderError) -> StubCursorCredentials {
        StubCursorCredentials(result: .failure(error))
    }

    func read() throws -> CursorCredential {
        try result.get()
    }
}

/// A limiter that never refuses, for tests about everything except pacing.
func unthrottled() -> EndpointRateLimiter {
    EndpointRateLimiter(minimumInterval: 0, initialBackoff: 0, maximumBackoff: 0)
}
