import Foundation
import SideNotchCore

/// Reads Cursor usage using the access token Cursor already stores on this machine.
///
/// ## What this talks to, and why
///
/// `GET https://api2.cursor.sh/auth/usage`, with the bearer token read from
/// `cursorAuth/accessToken` in Cursor's own `state.vscdb`. **Unofficial**: Cursor publishes
/// no usage API and no CLI that prints quota. `cursor --status` reports process
/// diagnostics — CPU, memory, PIDs — and nothing about entitlement.
///
/// ## The line this adapter does not cross
///
/// Cursor's web dashboard endpoints under `cursor.com/api/*` authenticate with a
/// `WorkosCursorSessionToken` browser cookie. Several comparable tools synthesize that
/// cookie by pasting the local JWT into the browser's cookie format, or read it out of
/// Safari and Chrome cookie jars directly. **This adapter does neither.** Harvesting
/// browser cookies is the scraping of authenticated sessions the project rules prohibit
/// outright, and forging a session cookie impersonates the user's browser to a service
/// that did not issue it one.
///
/// Presenting Cursor's own token to Cursor's own API is a different act: it is the same
/// credential the editor uses, for the same purpose, over the same transport. That is the
/// boundary — reuse the client's credential as a client, never reconstruct the browser's.
///
/// The cost of that line is real. The bearer endpoint reports the request-pool model; it
/// does not carry the newer usage-based-pricing dollar figures the web dashboard shows. A
/// partial honest reading is the right trade against a complete dishonest one.
///
/// ## Reliability
///
/// Lower than Claude's. The credential path is confirmed on this machine — the token is
/// present, well-formed, and 424 bytes of JWT. The response schema is taken from several
/// independent extensions that consume it, but has not been validated against a live
/// account here, so `CursorUsageDecoder` fails closed: an unrecognised payload yields
/// `.unavailable`, never a fabricated ring.
public struct CursorUsageProvider: UsageProvider {
    public let providerType: ProviderType = .cursor
    public let displayName = "Cursor"

    private let credentials: CursorCredentialReading
    private let http: any UsageHTTPPerforming
    private let limiter: EndpointRateLimiter
    private let endpoint: URL

    /// Legacy request-pool endpoint. Correct for older quota-based accounts, and null on
    /// everything else.
    public static let defaultEndpoint = URL(string: "https://api2.cursor.sh/auth/usage")!

    /// Cursor's dashboard service, spoken over Connect RPC.
    ///
    /// POST-only even though it is a read, empty body, and — the reason it is usable here —
    /// authenticated by the same bearer token the editor holds rather than by a browser
    /// session cookie. It stays on the right side of the boundary this adapter draws while
    /// returning the figures `/auth/usage` cannot: a real `totalPercentUsed`, the included
    /// allowance, and the billing cycle.
    public static let dashboardEndpoint = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    )!

    public init(
        credentials: CursorCredentialReading = CursorCredentialSource(),
        http: any UsageHTTPPerforming = UsageHTTPClient(),
        // Cursor has not been observed rate-limiting this endpoint, but a shared floor
        // keeps a hover-storm from turning into a request storm against any provider.
        limiter: EndpointRateLimiter = EndpointRateLimiter(minimumInterval: 120),
        endpoint: URL = CursorUsageProvider.defaultEndpoint
    ) {
        self.credentials = credentials
        self.http = http
        self.limiter = limiter
        self.endpoint = endpoint
    }

    public func fetchUsage() async throws -> UsageState {
        #if !os(macOS)
        return UsageState.unsupported(provider: providerType, reason: "macOS only")
        #else
        let credential: CursorCredential
        do {
            credential = try credentials.read()
        } catch let error as ProviderError {
            return state(for: error)
        }

        guard !credential.isExpired() else {
            // Cursor refreshes its own token when the editor next runs. We do not hold the
            // refresh token and will not mint one.
            return UsageState.unavailable(provider: providerType, reason: "Sign-in expired")
        }

        if let refusal = await limiter.claim() {
            Log.provider.debug("Cursor usage read deferred: \(String(describing: refusal))")
            return UsageState.unavailable(provider: providerType, reason: "Waiting to refresh")
        }

        // The dashboard service first: it is the only one that describes a modern account.
        let dashboard = await http.post(
            Self.dashboardEndpoint,
            headers: [
                "Authorization": "Bearer \(credential.accessToken.reveal())",
                "Content-Type": "application/json",
                // Connect RPC's protocol marker. Without it the service rejects the call.
                "Connect-Protocol-Version": "1",
                "User-Agent": ClaudeUsageProvider.userAgent,
            ],
            body: Data("{}".utf8)
        )

        if case .success(let data) = dashboard {
            await limiter.recordSuccess()
            let dto = try CursorPeriodUsageDecoder.decode(data)
            let unknown = CursorPeriodUsageDecoder.unknownKeys(in: data)
            if !unknown.isEmpty {
                Log.provider.notice(
                    "Cursor dashboard schema drift: unrecognised keys \(unknown.joined(separator: ","), privacy: .public)"
                )
            }
            return CursorPeriodUsageMapper.snapshot(from: dto, unknownKeys: unknown)
        }

        // Anything else falls through to the legacy request-pool endpoint. It reports
        // nothing useful on usage-based pricing, but it is the correct answer for an older
        // account still governed by a request quota — and it costs one request only when
        // the dashboard has already failed.
        let outcome = await http.get(
            endpoint,
            headers: [
                "Authorization": "Bearer \(credential.accessToken.reveal())",
                "Accept": "application/json",
                "User-Agent": ClaudeUsageProvider.userAgent,
            ]
        )

        switch outcome {
        case .success(let data):
            await limiter.recordSuccess()
            let response = try CursorUsageDecoder.decode(data)
            if !response.unknownKeys.isEmpty {
                Log.provider.notice(
                    "Cursor usage schema drift: unrecognised keys \(response.unknownKeys.joined(separator: ","), privacy: .public)"
                )
            }
            return CursorUsageMapper.snapshot(from: response)

        case .unauthorized(_):
            return UsageState.unavailable(provider: providerType, reason: "Sign in to Cursor")

        case .rateLimited(let retryAfter, _):
            await limiter.recordRateLimited(retryAfter: retryAfter)
            return UsageState.unavailable(provider: providerType, reason: "Rate limited")

        case .http(let status, _):
            await limiter.recordTransportFailure()
            Log.provider.error("Cursor usage HTTP \(status)")
            return UsageState.unavailable(provider: providerType, reason: "Service unavailable")

        case .transport(let detail):
            await limiter.recordTransportFailure()
            Log.provider.debug("Cursor usage transport failure: \(detail, privacy: .public)")
            return UsageState.unavailable(provider: providerType, reason: detail.railSafe)
        }
        #endif
    }

    private func state(for error: ProviderError) -> UsageState {
        switch error {
        case .notInstalled:
            UsageState.unavailable(provider: providerType, reason: "Cursor not installed")
        case .authenticationRequired:
            UsageState.unavailable(provider: providerType, reason: "Sign in to Cursor")
        case .unsupported(let reason):
            UsageState.unsupported(provider: providerType, reason: reason)
        default:
            UsageState.unavailable(
                provider: providerType, reason: error.userFacingDescription
            )
        }
    }
}
