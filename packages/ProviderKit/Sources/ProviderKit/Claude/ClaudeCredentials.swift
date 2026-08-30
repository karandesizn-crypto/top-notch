import Foundation
import SideNotchCore

#if canImport(Security)
import Security
#endif

/// Claude Code's OAuth state, reduced to the four fields a usage read needs.
///
/// **The refresh token is deliberately absent.** The stored blob contains one, and
/// omitting it from this type is the single most important safety decision in the Claude
/// integration. Anthropic rotates the refresh token on every use and revokes the entire
/// token family if a superseded one is presented — so a second process that refreshes
/// while Claude Code holds the current token can log the user out of their CLI. Not
/// decoding the field means no future edit to this adapter can perform a refresh by
/// accident; it would first have to add the field back, which is a conspicuous change.
///
/// When the endpoint rejects the token we report `authenticationRequired` and stop. Claude
/// Code refreshes on its own next invocation, and because the credential is re-read on
/// every fetch, we pick up the rotated value with no coordination.
public struct ClaudeOAuthCredential: Sendable {
    public let accessToken: Secret
    /// Absolute expiry, when the blob states one.
    ///
    /// **Advisory only.** See `isExpired(_:)` — this is a claim the store makes about
    /// itself, not an authority on whether the endpoint will accept the token.
    public let expiresAt: Date?
    public let scopes: [String]
    /// e.g. "max", "pro". Display-safe; not an account identifier.
    public let subscriptionType: String?
    /// Which store the credential came from, for diagnostics.
    public let origin: Origin

    /// Where a credential was found. Worth recording because the two stores can disagree —
    /// a stale `~/.claude/.credentials.json` left over from an earlier login will happily
    /// parse while the keychain holds the live one.
    public enum Origin: String, Sendable {
        case keychain
        case file
        case injected
    }

    public init(
        accessToken: Secret,
        expiresAt: Date?,
        scopes: [String],
        subscriptionType: String?,
        origin: Origin = .injected
    ) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.origin = origin
    }

    /// Whether the store *claims* this token has expired.
    ///
    /// Deliberately not used as a gate on making the request. Treating it as one produced
    /// a real failure on a real machine: a credential whose `expiresAt` sat in the past
    /// made the adapter report "Sign-in expired" indefinitely without ever asking the
    /// endpoint, while the user was signed in and working. The stored expiry can be stale,
    /// can come from a superseded credential file, or can simply be a field we are reading
    /// under the wrong assumption — and none of those are knowable from here.
    ///
    /// The endpoint is the only authority on whether a token works. So this now informs
    /// the *wording* of a failure rather than preventing the attempt: a 401 on a
    /// nominally-expired token is "Sign-in expired", the same 401 on a live-looking one is
    /// "Sign-in required". One wasted request is a much cheaper mistake than a permanently
    /// blank provider.
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }

    /// The usage endpoint requires `user:profile`. A token minted with only
    /// `user:inference` authenticates fine and then returns 403 forever, so checking the
    /// scope up front is the difference between "sign in again" (useless — the user
    /// already is) and an honest structural answer.
    public var grantsUsageRead: Bool {
        scopes.contains("user:profile")
    }
}

/// Where the credential comes from. Split out so tests never touch the real keychain.
public protocol ClaudeCredentialReading: Sendable {
    func read() throws -> ClaudeOAuthCredential
}

/// Reads Claude Code's own OAuth state, without modifying it.
///
/// Two locations, in the order Claude Code itself prefers them on macOS:
///
/// 1. Keychain generic password, service `Claude Code-credentials`. The canonical store.
/// 2. `~/.claude/.credentials.json`. Used by some installs and by non-macOS hosts.
///
/// Every read goes to the source; nothing is cached here. Claude Code rotates this item
/// periodically, and a cached copy would go stale into an authorization error that looks
/// like a bug in this app.
///
/// Read-only in the strict sense: `SecItemCopyMatching` only, never `SecItemUpdate` or
/// `SecItemDelete`, and the file path is opened for reading. The user's login is never
/// modified, refreshed, or invalidated by anything in this file.
public struct ClaudeCredentialSource: ClaudeCredentialReading {
    /// Claude Code's keychain service name.
    public static let keychainService = "Claude Code-credentials"

    private let fileURL: URL
    private let keychainEnabled: Bool

    public init(
        fileURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/.credentials.json"),
        keychainEnabled: Bool = true
    ) {
        self.fileURL = fileURL
        self.keychainEnabled = keychainEnabled
    }

    /// Gathers every credential this machine holds and returns the best one.
    ///
    /// Both stores are consulted, not just the first that answers. Short-circuiting on a
    /// successful keychain read looks reasonable and is subtly wrong: the two stores can
    /// disagree, and the one that answers first is not necessarily the one with a live
    /// token. Claude Code writes to whichever its install uses, leaving the other frozen at
    /// whatever it last held — so a stale keychain item can shadow a perfectly good file,
    /// and the adapter would report a lapsed sign-in with a working credential sitting on
    /// disk beside it.
    ///
    /// Ranking across the union costs one extra file read and removes that whole class of
    /// failure.
    public func read() throws -> ClaudeOAuthCredential {
        var candidates: [ClaudeOAuthCredential] = []
        var firstFailure: ProviderError?

        #if os(macOS)
        if keychainEnabled {
            do {
                candidates += try Self.readKeychainItems().compactMap {
                    try? Self.parse($0, origin: .keychain)
                }
            } catch let error as ProviderError {
                // A missing item is normal on installs that use the file store; a denied
                // ACL is not. Either way the file may still answer, so record and continue.
                firstFailure = error
            }
        }
        #endif

        if let data = try? Data(contentsOf: fileURL) {
            do {
                candidates.append(try Self.parse(data, origin: .file))
            } catch let error as ProviderError {
                firstFailure = firstFailure ?? error
            }
        }

        if let best = Self.best(of: candidates) {
            return best
        }
        throw firstFailure ?? .authenticationRequired
    }

    #if os(macOS)
    /// Fetches every matching generic-password item. Never logs the results.
    ///
    /// **All** matches, not one. `kSecMatchLimitOne` returns an arbitrary item when the
    /// service name has more than one entry — which happens routinely here: signing out
    /// and back in, or switching accounts, can leave a superseded item beside the live
    /// one. Picking blind means intermittently authenticating with a dead token and
    /// reporting a lapsed login while the user is signed in, with nothing in the failure
    /// to suggest that a *different* item would have worked.
    ///
    /// A denied ACL surfaces as `authenticationRequired` rather than an error, because the
    /// remedy is the user approving access in the system prompt — a sign-in-shaped
    /// problem, not a malfunction.
    static func readKeychainItems() throws -> [Data] {
        // `kSecMatchLimitAll` must be paired with `kSecReturnAttributes` on macOS. Asking
        // for bare data across multiple items returns errSecParam (-50) rather than the
        // array you would expect, so each match arrives as a dictionary and the payload
        // sits under `kSecValueData`.
        let allQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        var status = SecItemCopyMatching(allQuery as CFDictionary, &item)

        if status == errSecSuccess, let payloads = Self.payloads(from: item), !payloads.isEmpty {
            return payloads
        }

        // Fall back to the single-item form. Keychain behaviour varies across macOS
        // releases and item provenance, and one credential beats none — we simply lose the
        // ability to choose between duplicates.
        if status != errSecItemNotFound {
            let oneQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            item = nil
            status = SecItemCopyMatching(oneQuery as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data {
                return [data]
            }
        }

        switch status {
        case errSecItemNotFound:
            throw ProviderError.authenticationRequired
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            throw ProviderError.authenticationRequired
        default:
            throw ProviderError.unknown(detail: "Keychain status \(status)")
        }
    }

    /// Pulls the password bytes out of whichever shape the keychain returned.
    static func payloads(from item: CFTypeRef?) -> [Data]? {
        if let dictionaries = item as? [[String: Any]] {
            return dictionaries.compactMap { $0[kSecValueData as String] as? Data }
        }
        if let dictionary = item as? [String: Any] {
            return (dictionary[kSecValueData as String] as? Data).map { [$0] }
        }
        if let many = item as? [Data] { return many }
        if let one = item as? Data { return [one] }
        return nil
    }
    #endif

    /// Chooses between credentials found in the same store.
    ///
    /// Ordering: a token that can actually read usage beats one that cannot, and among
    /// equals the one that expires latest wins. A credential with no stated expiry sorts
    /// below a live one but above a lapsed one — unknown is not the same as gone.
    static func best(
        of candidates: [ClaudeOAuthCredential], now: Date = Date()
    ) -> ClaudeOAuthCredential? {
        candidates.max { left, right in
            isWorse(left, than: right, now: now)
        }
    }

    /// Lexicographic across three keys, written out because Swift tuples are not
    /// `Comparable` and a synthesized ordering would hide which key dominates.
    private static func isWorse(
        _ left: ClaudeOAuthCredential,
        than right: ClaudeOAuthCredential,
        now: Date
    ) -> Bool {
        // 1. Usable scope dominates everything: a token that cannot read usage is no use
        //    however fresh it is.
        if left.grantsUsageRead != right.grantsUsageRead {
            return !left.grantsUsageRead
        }
        // 2. Then not-yet-expired.
        let leftLive = !left.isExpired(now: now)
        let rightLive = !right.isExpired(now: now)
        if leftLive != rightLive {
            return !leftLive
        }
        // 3. Then whichever survives longest.
        return (left.expiresAt?.timeIntervalSince1970 ?? 0)
            < (right.expiresAt?.timeIntervalSince1970 ?? 0)
    }

    /// Decodes the credential blob.
    ///
    /// Hand-rolled rather than `Codable` because the surrounding document carries fields
    /// we must not materialize — the refresh token above all — and a synthesized decoder
    /// invites someone to add them later for symmetry.
    static func parse(
        _ data: Data, origin: ClaudeOAuthCredential.Origin = .injected
    ) throws -> ClaudeOAuthCredential {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderError.invalidResponse(detail: "Credential store is not JSON")
        }
        guard let oauth = root["claudeAiOauth"] as? [String: Any] else {
            // `mcpOAuth` can be present alone when the user has only authorized MCP
            // servers; that is a signed-out state for our purposes, not a broken store.
            throw ProviderError.authenticationRequired
        }
        guard
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw ProviderError.authenticationRequired
        }

        let expiresAt = (oauth["expiresAt"] as? Double).map(Self.epochDate)

        return ClaudeOAuthCredential(
            accessToken: Secret(token),
            expiresAt: expiresAt,
            scopes: oauth["scopes"] as? [String] ?? [],
            subscriptionType: oauth["subscriptionType"] as? String,
            origin: origin
        )
    }

    /// Interprets an epoch timestamp whose unit is not stated.
    ///
    /// Claude Code writes `expiresAt` in milliseconds, but the field carries no unit and
    /// the file format is not ours. Assuming milliseconds outright is the kind of guess
    /// that fails silently in the worst direction: a seconds value divided by 1000 lands
    /// in 1970, every token reads as expired, and the provider reports "Sign-in expired"
    /// forever while the user is plainly signed in.
    ///
    /// The two units are never ambiguous in practice. A present-day seconds timestamp is
    /// ~1.8×10⁹; the same instant in milliseconds is ~1.8×10¹². The threshold sits between
    /// them by nine orders of magnitude — as seconds it is the year 5138, as milliseconds
    /// it is 1973 — so no real credential can fall on the wrong side.
    static func epochDate(_ value: Double) -> Date {
        let millisecondThreshold = 100_000_000_000.0
        return value > millisecondThreshold
            ? Date(timeIntervalSince1970: value / 1000)
            : Date(timeIntervalSince1970: value)
    }
}
