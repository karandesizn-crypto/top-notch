import Foundation

/// What the transport can report back, separated so adapters can react correctly.
///
/// `rateLimited` is its own case rather than folded into `http` because it is the one
/// status that must feed the backoff ladder instead of the error path.
public enum HTTPOutcome: Sendable {
    case success(Data)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int)
    case transport(detail: String)
}

/// The seam that keeps the network out of unit tests.
///
/// Adapters depend on this rather than the concrete client, so every branch of their
/// outcome handling — 401, 429, 500, offline — can be exercised deterministically without
/// a socket or a credential.
public protocol UsageHTTPPerforming: Sendable {
    func get(_ url: URL, headers: [String: String]) async -> HTTPOutcome
}

/// The single place in SideNotch that touches the network.
///
/// Configured to be forgetful. The session is ephemeral, cookie handling is off, and the
/// URL cache is nil, so no credential-bearing request can leave a trace in the shared
/// cookie jar or on disk — which matters here because the tokens involved belong to the
/// user's Claude Code and Cursor logins, not to us. Nothing is persisted between calls,
/// and nothing is shared with `URLSession.shared`.
///
/// Deliberately small: one method, no retry loop, no queueing. Pacing is
/// `EndpointRateLimiter`'s job, and retries against an endpoint that punishes bursts are
/// exactly the wrong instinct.
public struct UsageHTTPClient: UsageHTTPPerforming {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
        self.timeout = timeout
    }

    /// Performs one GET. `headers` is the only place a `Secret` is revealed.
    public func get(_ url: URL, headers: [String: String]) async -> HTTPOutcome {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .transport(detail: "Non-HTTP response")
            }
            switch http.statusCode {
            case 200...299:
                return .success(data)
            case 401, 403:
                return .unauthorized
            case 429:
                let header = http.value(forHTTPHeaderField: "Retry-After")
                return .rateLimited(retryAfter: header.flatMap(TimeInterval.init))
            default:
                return .http(status: http.statusCode)
            }
        } catch {
            // `localizedDescription` on a URLError names the host and the failure kind.
            // Neither is a secret, and both are what makes a bug report actionable.
            return .transport(detail: (error as? URLError)?.code.diagnosticName
                ?? "Request failed")
        }
    }
}

private extension URLError.Code {
    /// A short, stable name for the common transport failures.
    ///
    /// Preferred over `localizedDescription` because that is locale-dependent, and these
    /// strings end up in comparisons and logs.
    var diagnosticName: String {
        switch self {
        case .notConnectedToInternet: "Offline"
        case .timedOut: "Timed out"
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: "Host unreachable"
        case .networkConnectionLost: "Connection lost"
        case .secureConnectionFailed, .serverCertificateUntrusted: "TLS failure"
        default: "Request failed"
        }
    }
}
