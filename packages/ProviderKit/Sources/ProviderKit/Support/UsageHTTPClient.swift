import Foundation

/// What the transport can report back, separated so adapters can react correctly.
///
/// `rateLimited` is its own case rather than folded into `http` because it is the one
/// status that must feed the backoff ladder instead of the error path.
public enum HTTPOutcome: Sendable {
    case success(Data)
    case unauthorized(detail: String? = nil)
    case rateLimited(retryAfter: TimeInterval? = nil, detail: String? = nil)
    case http(status: Int, detail: String? = nil)
    case transport(detail: String)
}

/// Pulls the machine-readable part out of a provider's error body.
///
/// A bare status code is not enough to act on. Anthropic returns 429 for a rate limit and
/// 401 for a lapsed token, but it also returns those codes for reasons the `type` field
/// distinguishes and the number does not — and while chasing a 401 on a live account, "is
/// this an expired token or a rate limit wearing a different hat" was exactly the question
/// that could not be answered from the status alone.
///
/// Only `error.type` is taken verbatim; the human message is truncated hard. Neither ever
/// reaches user-facing copy — this goes to logs and diagnostics metadata only, because an
/// error body is provider-controlled text and does not belong in the UI.
enum HTTPErrorDetail {
    static let messageLimit = 120

    static func extract(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Anthropic: {"error":{"type":"rate_limit_error","message":"..."}}
        if let error = root["error"] as? [String: Any] {
            let type = error["type"] as? String
            let message = (error["message"] as? String).map(truncate)
            return [type, message].compactMap { $0 }.joined(separator: ": ")
                .nilIfEmpty
        }
        // Connect RPC: {"code":"unauthenticated","message":"..."}
        if let code = root["code"] as? String {
            let message = (root["message"] as? String).map(truncate)
            return [code, message].compactMap { $0 }.joined(separator: ": ").nilIfEmpty
        }
        return nil
    }

    private static func truncate(_ text: String) -> String {
        text.count <= messageLimit
            ? text
            : String(text.prefix(messageLimit)) + "…"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The seam that keeps the network out of unit tests.
///
/// Adapters depend on this rather than the concrete client, so every branch of their
/// outcome handling — 401, 429, 500, offline — can be exercised deterministically without
/// a socket or a credential.
public protocol UsageHTTPPerforming: Sendable {
    func get(_ url: URL, headers: [String: String]) async -> HTTPOutcome
    func post(_ url: URL, headers: [String: String], body: Data) async -> HTTPOutcome
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
        await send("GET", url, headers: headers, body: nil)
    }

    /// Performs one POST.
    ///
    /// Needed because Cursor's dashboard service speaks Connect RPC, which is POST-only
    /// even for reads — `GetCurrentPeriodUsage` takes an empty body and returns the usage
    /// figures. Still a read: nothing here mutates provider state.
    public func post(_ url: URL, headers: [String: String], body: Data) async -> HTTPOutcome {
        await send("POST", url, headers: headers, body: body)
    }

    private func send(
        _ method: String, _ url: URL, headers: [String: String], body: Data?
    ) async -> HTTPOutcome {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
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
                return .unauthorized(detail: HTTPErrorDetail.extract(from: data))
            case 429:
                let header = http.value(forHTTPHeaderField: "Retry-After")
                return .rateLimited(
                    retryAfter: header.flatMap(TimeInterval.init),
                    detail: HTTPErrorDetail.extract(from: data)
                )
            default:
                return .http(
                    status: http.statusCode,
                    detail: HTTPErrorDetail.extract(from: data)
                )
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
