import Foundation
@testable import ProviderKit

/// Test doubles for the two seams that would otherwise reach outside the process.
///
/// Every provider test in this target runs through these. Nothing in the suite may open a
/// socket or touch the real keychain: a unit test that depends on the user being signed in
/// to Claude Code fails on a colleague's machine and in CI, and one that calls the live
/// usage endpoint burns the rate limit the product depends on.

/// Returns a canned HTTP outcome without a network call.
struct StubHTTPClient: UsageHTTPPerforming {
    let outcome: HTTPOutcome
    /// Records the headers of the last request so tests can assert on them.
    let recorder: HeaderRecorder?

    init(_ outcome: HTTPOutcome, recorder: HeaderRecorder? = nil) {
        self.outcome = outcome
        self.recorder = recorder
    }

    func get(_ url: URL, headers: [String: String]) async -> HTTPOutcome {
        await recorder?.record(url: url, headers: headers)
        return outcome
    }
}

/// Captures what a provider actually put on the wire.
actor HeaderRecorder {
    private(set) var url: URL?
    private(set) var headers: [String: String] = [:]
    private(set) var callCount = 0

    func record(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
        callCount += 1
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
