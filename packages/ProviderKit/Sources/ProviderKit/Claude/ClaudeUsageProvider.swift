import Foundation
import SideNotchCore

/// Reads Claude Code's live usage from the endpoint Claude Code's own `/usage` uses.
///
/// ## What this talks to, and why
///
/// `GET https://api.anthropic.com/api/oauth/usage`, authorized with the access token that
/// Claude Code already stores on this machine. **This endpoint is undocumented.** It is
/// not in Anthropic's public API reference, it is gated behind the `oauth-2025-04-20` beta
/// header, and it can change or vanish without notice. Everything below is built on the
/// assumption that it eventually will.
///
/// It is used anyway because the alternatives are worse and were each ruled out with
/// evidence (`docs/PHASE_4_DATA_SOURCE_AUDIT.md`): the CLI exposes no usage command; the
/// `~/.claude.json` cache measured twelve days stale; and both documented Admin API usage
/// endpoints are organization-scoped, unavailable to individual accounts, and carry no
/// limit, reset, or percentage field at all. Live figures exist in exactly one place.
///
/// ## The safety rules this adapter follows
///
/// - **It never refreshes the token.** `ClaudeOAuthCredential` does not even decode the
///   refresh token. Anthropic rotates refresh tokens and revokes the whole family when a
///   superseded one is presented, so a second refresher racing Claude Code can sign the
///   user out of their CLI. When the endpoint rejects a token this reports it and waits;
///   Claude Code refreshes on its own next run and we read the new value.
/// - **The stored expiry is advisory, not a gate.** Gating on it made this adapter answer
///   "Sign-in expired" indefinitely on a machine whose keychain `expiresAt` had lapsed
///   while the login was healthy. The endpoint decides; the stored claim only picks the
///   wording when a request is actually refused.
/// - **It re-reads the credential every fetch.** The keychain item is rotated
///   periodically, and a cached token would decay into a spurious auth error.
/// - **It calls at most once per three minutes.** The endpoint rate-limits hard, sends no
///   `Retry-After`, and stays limited for hours; see `EndpointRateLimiter`.
/// - **It never logs or persists the token.** The value lives in a `Secret` and is
///   revealed once, inline, in the header dictionary.
/// - **A refused or failed read yields no figures.** It returns `.unavailable`, which the
///   manager renders as the previous reading marked `.cached` — never a stale number
///   dressed as live.
///
/// ## Reliability
///
/// Medium. The transport and the schema are both unofficial. Field names are confirmed
/// against three independent implementations, and `ClaudeUsageDecoder` fails closed on
/// anything it does not recognise, so the realistic failure mode is "Claude shows
/// unavailable after an Anthropic change", not a wrong number.
public struct ClaudeUsageProvider: UsageProvider {
    public let providerType: ProviderType = .claude
    public let displayName = "Claude"

    private let credentials: ClaudeCredentialReading
    private let http: any UsageHTTPPerforming
    private let limiter: EndpointRateLimiter
    private let endpoint: URL

    /// The beta gate the endpoint requires. Pinned, and part of the drift surface: if
    /// Anthropic retires this value the request starts failing, which is the safe
    /// direction.
    static let betaHeader = "oauth-2025-04-20"

    public static let defaultEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(
        credentials: ClaudeCredentialReading = ClaudeCredentialSource(),
        http: any UsageHTTPPerforming = UsageHTTPClient(),
        limiter: EndpointRateLimiter = EndpointRateLimiter(),
        endpoint: URL = ClaudeUsageProvider.defaultEndpoint
    ) {
        self.credentials = credentials
        self.http = http
        self.limiter = limiter
        self.endpoint = endpoint
    }

    public func fetchUsage() async throws -> UsageState {
        #if !os(macOS)
        return UsageState.unsupported(
            provider: providerType, reason: "macOS only"
        )
        #else
        let credential: ClaudeOAuthCredential
        do {
            credential = try credentials.read()
        } catch let error as ProviderError {
            return state(for: error)
        }

        // Structural: no retry and no re-sign-in fixes a token minted without the scope,
        // so this is `.unsupported` rather than `.unavailable`.
        guard credential.grantsUsageRead else {
            return UsageState.unsupported(
                provider: providerType, reason: "Usage scope not granted"
            )
        }

        // The stored expiry is deliberately NOT a gate. On a real machine a credential
        // whose `expiresAt` had already passed made this adapter answer "Sign-in expired"
        // forever without ever asking the endpoint, while Claude Code itself was working
        // fine. The endpoint is the authority; the stored claim only picks the wording if
        // the request is actually refused.
        let looksExpired = credential.isExpired()

        if let refusal = await limiter.claim() {
            Log.provider.debug("Claude usage read deferred: \(String(describing: refusal))")
            // `.unavailable` is retryable, so `UsageManager` keeps the previous figures and
            // re-marks them `.cached`. That is the honest rendering of "we have numbers,
            // they are just not from this second".
            return UsageState.unavailable(
                provider: providerType, reason: "Waiting to refresh"
            )
        }

        let outcome = await http.get(
            endpoint,
            headers: [
                "Authorization": "Bearer \(credential.accessToken.reveal())",
                "anthropic-beta": Self.betaHeader,
                "Accept": "application/json",
                // Identifying the client is what lets Anthropic tell a well-behaved poller
                // from a hot loop, and comparable tools report it materially affects how
                // quickly the endpoint starts refusing.
                "User-Agent": Self.userAgent,
            ]
        )

        switch outcome {
        case .success(let data):
            await limiter.recordSuccess()
            let response = try ClaudeUsageDecoder.decode(data)
            if !response.unknownKeys.isEmpty {
                Log.provider.notice(
                    "Claude usage schema drift: unrecognised keys \(response.unknownKeys.joined(separator: ","), privacy: .public)"
                )
            }
            return ClaudeUsageMapper.snapshot(
                from: response,
                plan: credential.subscriptionType,
                credentialOrigin: credential.origin
            )

        case .unauthorized:
            // The token was readable but refused by the endpoint. Do not refresh — that is
            // the account-safety rule. Claude Code will mint a new one on its next run and
            // the following poll picks it up.
            //
            // The origin is recorded because a rejection is ambiguous without it: the same
            // 401 means "your login lapsed" if it came from the keychain, and "we read a
            // superseded credential file" if it came from disk. Those need different fixes.
            return UsageState(
                provider: providerType,
                status: .unavailable,
                source: .unavailable,
                lastUpdated: Date(),
                failure: looksExpired ? "Sign-in expired" : "Sign-in required",
                metadata: [
                    "credentialSource": credential.origin.rawValue,
                    "storedExpiryPassed": String(looksExpired),
                    // A timestamp, not a secret. Distinguishes a genuinely lapsed login
                    // from a field we are reading under the wrong unit — a duration
                    // misread as an absolute time lands in 1970 and looks identical to an
                    // expired token from every other angle.
                    "storedExpiry": credential.expiresAt
                        .map { ISO8601DateFormatter().string(from: $0) } ?? "absent",
                ]
            )

        case .rateLimited(let retryAfter):
            await limiter.recordRateLimited(retryAfter: retryAfter)
            return UsageState.unavailable(
                provider: providerType, reason: "Rate limited"
            )

        case .http(let status):
            await limiter.recordTransportFailure()
            Log.provider.error("Claude usage HTTP \(status)")
            return UsageState.unavailable(
                provider: providerType, reason: "Service unavailable"
            )

        case .transport(let detail):
            await limiter.recordTransportFailure()
            Log.provider.debug("Claude usage transport failure: \(detail, privacy: .public)")
            return UsageState.unavailable(
                provider: providerType, reason: detail
            )
        }
        #endif
    }

    /// Client identifier sent with every request.
    static let userAgent = "SideNotch/1.0 (macOS; usage-monitor)"

    /// Maps a credential-read failure onto the state the UI should show.
    ///
    /// The diagnostic detail goes to metadata rather than into the failure string: the
    /// rail renders `failure` in 185pt and an OSStatus would truncate the useful half
    /// away, but without it anywhere a keychain problem is indistinguishable from every
    /// other "Unavailable".
    private func state(for error: ProviderError) -> UsageState {
        switch error {
        case .unsupported(let reason):
            return UsageState.unsupported(provider: providerType, reason: reason)
        case .authenticationRequired:
            return UsageState.unavailable(
                provider: providerType, reason: "Sign in to Claude Code"
            )
        default:
            var metadata: [String: String] = [:]
            switch error {
            case .unknown(let detail), .invalidResponse(let detail), .network(let detail):
                metadata["credentialReadDetail"] = detail
            default:
                break
            }
            return UsageState(
                provider: providerType,
                status: error.status,
                source: .unavailable,
                lastUpdated: Date(),
                failure: error.userFacingDescription,
                metadata: metadata
            )
        }
    }
}
