import Foundation
import SideNotchCore

#if canImport(SQLite3)
import SQLite3
#endif

/// Cursor's locally stored access token, plus what its JWT says about itself.
///
/// Only the access token is taken. `cursorAuth/refreshToken` sits in the same table and is
/// deliberately never read, for the same reason as Claude's: possessing a refresh token is
/// the precondition for accidentally rotating one, and this app has no business extending
/// the lifetime of the user's Cursor session.
public struct CursorCredential: Sendable {
    public let accessToken: Secret
    /// From the JWT's `exp` claim, when present.
    public let expiresAt: Date?

    public init(accessToken: Secret, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// A minute of headroom so a token that dies in flight is not misread as a rejection.
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}

public protocol CursorCredentialReading: Sendable {
    func read() throws -> CursorCredential
}

/// Reads `cursorAuth/accessToken` out of Cursor's global state database.
///
/// The earlier audit concluded Cursor had nothing local to read. That was wrong, and the
/// mistake is worth recording: the sweep looked for *usage figures* — keys matching
/// `usage`, `quota`, `limit` — found none, and stopped. It never occurred to the sweep to
/// look for the *credential* that would let us ask for the figures, which was sitting in
/// the same table under `cursorAuth/accessToken` the whole time.
///
/// ## Reading a 4.9 GB database that another process owns
///
/// The file is large and live. Two rules keep this safe:
///
/// - **Read-only, always.** `SQLITE_OPEN_READONLY`, no writes, no schema access, one
///   `SELECT` of one row by exact key.
/// - **Never take a lock Cursor could wait on.** The connection is opened `mode=ro` first,
///   which respects the write-ahead log and so returns the current token. If that fails —
///   typically because the `-shm` sidecar is not readable — it retries with `immutable=1`,
///   which cannot contend at all but may return a pre-WAL value. A stale token is a
///   recoverable outcome (the request 401s and the provider reports unavailable), whereas
///   blocking Cursor's own writes is not.
public struct CursorCredentialSource: CursorCredentialReading {
    public static let tokenKey = "cursorAuth/accessToken"

    public static let defaultDatabaseURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    private let databaseURL: URL

    public init(databaseURL: URL = CursorCredentialSource.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    public func read() throws -> CursorCredential {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw ProviderError.notInstalled
        }

        #if canImport(SQLite3)
        let token = try Self.readToken(from: databaseURL)
        guard !token.isEmpty else { throw ProviderError.authenticationRequired }
        return CursorCredential(
            accessToken: Secret(token),
            expiresAt: Self.expiry(ofJWT: token)
        )
        #else
        throw ProviderError.unsupported(reason: "SQLite unavailable")
        #endif
    }

    #if canImport(SQLite3)
    /// Opens read-only and fetches exactly one value.
    static func readToken(from url: URL) throws -> String {
        // `mode=ro` first for correctness, `immutable=1` as the never-contend fallback.
        let escaped = url.path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? url.path
        let candidates = ["file:\(escaped)?mode=ro", "file:\(escaped)?immutable=1"]

        var lastStatus: Int32 = SQLITE_OK
        for uri in candidates {
            var handle: OpaquePointer?
            let status = sqlite3_open_v2(
                uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil
            )
            guard status == SQLITE_OK, let handle else {
                lastStatus = status
                if handle != nil { sqlite3_close_v2(handle) }
                continue
            }
            defer { sqlite3_close_v2(handle) }

            // Busy timeout kept short: if Cursor is mid-checkpoint we would rather report
            // unavailable this cycle than sit on the handle.
            sqlite3_busy_timeout(handle, 250)

            if let value = try? selectValue(handle: handle, key: tokenKey) {
                return value
            }
        }
        throw ProviderError.unknown(detail: "Could not open Cursor state (sqlite \(lastStatus))")
    }

    /// One parameterized `SELECT`. Parameterized rather than interpolated because a
    /// hardcoded key is still worth binding — it keeps the habit intact for the next query.
    private static func selectValue(handle: OpaquePointer, key: String) throws -> String {
        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ProviderError.unknown(detail: "Cursor state query failed to prepare")
        }
        defer { sqlite3_finalize(statement) }

        // SQLITE_TRANSIENT: sqlite must copy the bytes, since `key` may not outlive the call.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ProviderError.authenticationRequired
        }
        guard let bytes = sqlite3_column_text(statement, 0) else {
            throw ProviderError.authenticationRequired
        }
        return String(cString: bytes)
    }
    #endif

    /// Reads the `exp` claim without verifying the signature.
    ///
    /// Verification would be pointless here — we are not authenticating the token, only
    /// asking whether it is worth spending a request on. The signature is Cursor's to
    /// check. Returns nil for anything that is not a well-formed JWT, which the caller
    /// treats as "expiry unknown", not "expired".
    static func expiry(ofJWT token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        guard let payload = base64URLDecode(String(segments[1])) else { return nil }
        guard
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }

        if let exp = object["exp"] as? Double { return Date(timeIntervalSince1970: exp) }
        if let exp = object["exp"] as? Int { return Date(timeIntervalSince1970: TimeInterval(exp)) }
        return nil
    }

    /// Base64url with the padding restored.
    static func base64URLDecode(_ input: String) -> Data? {
        var text = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder > 0 {
            text.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: text)
    }
}
