# Provider Integrations

**Date:** 2026-08-30
**Supersedes the Claude and Cursor verdicts in** `PHASE_4_DATA_SOURCE_AUDIT.md`.

The Phase 4 audit ruled Claude Code and Cursor unsupported. That conclusion was reached by
asking "is there a documented API?" rather than "is there a safe, reproducible mechanism?"
Both now have working adapters. This document records what each one does, how far it can be
trusted, and where it breaks.

One correction is worth stating plainly, because it shaped the wrong answer for two phases:
the Cursor sweep searched `state.vscdb` for *usage figures* — keys matching `usage`,
`quota`, `limit` — found none, and concluded the data was unreachable. It never looked for
the **credential** that would let us ask for the figures, which was in the same table under
`cursorAuth/accessToken` the whole time. Absence of an answer is not absence of a route.

---

## Summary

| Provider | Source | Official | Live-verified | Confidence |
|---|---|---|---|---|
| **Codex** | `codex app-server` JSON-RPC over stdio | Official CLI surface | ✅ figures returned | **High** |
| **Claude** | `api.anthropic.com/api/oauth/usage` + Keychain token | **Unofficial** | ⚠️ auth path verified; success path blocked by a lapsed token | **Medium** |
| **Cursor** | `api2.cursor.sh/auth/usage` + `state.vscdb` token | **Unofficial** | ✅ 200 + decoded | **Medium-low** |

---

## Codex — unchanged

Already covered in `CODEX_INTEGRATION.md`. Local subprocess, no network, no credentials,
zero schema drift at last check. Nothing in this phase touched it.

---

## Claude Code

### Data source
`GET https://api.anthropic.com/api/oauth/usage` — the endpoint behind Claude Code's own
`/usage` command.

### Official or unofficial
**Unofficial.** Not in Anthropic's public API reference, gated behind the
`anthropic-beta: oauth-2025-04-20` header. It can change or disappear without notice.

The documented alternatives were re-checked and remain unusable for this purpose: both
`usage_report/messages` and `usage_report/claude_code` are Admin API, organization-scoped,
explicitly *"unavailable for individual accounts"*, and carry no limit, reset, or
percentage field. There is no supported route to a subscription's own limits.

### Authentication
Reuses Claude Code's existing login. No credential is ever requested from the user.

1. macOS Keychain, generic password, service `Claude Code-credentials`.
2. Fallback `~/.claude/.credentials.json` for installs that use the file store.

**Every match is fetched, not the first one.** `kSecMatchLimitOne` returns an arbitrary
item when several exist — which happens after signing out and back in — so the adapter
reads all of them and picks by: usable scope first, then not-expired, then latest expiry.
On macOS `kSecMatchLimitAll` must be paired with `kSecReturnAttributes`; asking for bare
data across multiple items returns `errSecParam` (-50), which cost a debugging cycle to
find and is now handled with a fallback to the single-item query.

### Fields obtained
`five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet` — each `{ utilization,
resets_at }`. Plan name comes from the credential's `subscriptionType`.

### Refresh
Poll on the app's normal schedule, floored at **one request per 180 seconds** by
`EndpointRateLimiter`. On HTTP 429 the floor becomes a backoff ladder: 5 → 10 → 20 → 30
minutes, capped.

This floor is not conservatism. The endpoint rate-limits after a short burst, returns no
`Retry-After` to negotiate with, stays limited for hours, and the issue requesting a
documented safe interval was closed as not planned. The floor was confirmed the hard way
during this phase: six probe runs in a few minutes earned a 429.

The app's user-facing refresh setting allows 30 seconds. That is deliberately *not* raised
to 180 — a faster setting simply means more claims get refused locally, which costs
nothing, rather than more requests reaching Anthropic.

### Caching
Adapter holds nothing. `FileUsageCache` persists the last `.available` snapshot; a refused
or failed read returns `.unavailable`, which is retryable, so `UsageManager` re-serves the
previous figures re-marked `.cached`. A stale figure is never presented as live.

### Failure behaviour
| Condition | Result |
|---|---|
| No credential | `.unavailable` — "Sign in to Claude Code" |
| Token lacks `user:profile` | `.unsupported` — structural, not retried |
| Rate-limit floor / backoff | `.unavailable` — previous figures re-served as `.cached` |
| 401 / 403 | `.unavailable` — "Sign-in expired" or "Sign-in required" |
| 429 | `.unavailable`, backoff armed |
| 5xx, offline | `.unavailable` |
| Unrecognised schema | throws → `.error` |

### Drift protection
`ClaudeUsageDecoder` fails closed. If no known window key is present it throws, naming the
keys it did see. Unrecognised top-level keys are recorded in `metadata.schemaUnknownKeys`
and logged. A renamed schema therefore surfaces as "unavailable", never as a confident 0%.

### Security
- **The refresh token is never decoded.** Anthropic rotates refresh tokens and revokes the
  whole family when a superseded one is presented, so a second refresher racing Claude Code
  can sign the user out of their CLI. Omitting the field from `ClaudeOAuthCredential` means
  no future edit can refresh by accident — it would have to add the field back first.
- Read-only: `SecItemCopyMatching` only. Never `SecItemUpdate`, never `SecItemDelete`.
- The token lives in `Secret`, which redacts under `print`, interpolation, and
  `String(describing:)`, and **throws** if encoded. It is revealed once, inline, in the
  header dictionary.
- Ephemeral `URLSession`: cookies off, URL cache nil, nothing shared with `URLSession.shared`.
- Credential re-read every fetch, never held between calls.

### Known limitations
1. **Undocumented endpoint.** Assume it will break.
2. **We cannot renew a lapsed token** — by design. When Claude Code's *persisted* access
   token expires, usage is unavailable until Claude Code writes a fresh one.
3. **The success path is not live-verified.** On this machine the keychain credential's
   `expiresAt` is `2026-08-29T16:44:53Z` and the endpoint returns 401. Everything up to and
   including authentication is confirmed working — the keychain item is found, parsed, and
   sent — but no 200 has been observed. The decoder is exercised only by fixtures.
4. Org-managed accounts may mint tokens without `user:profile`; those report unsupported.

---

## Cursor

### Data source
`GET https://api2.cursor.sh/auth/usage`, bearer-authenticated with the token from
`cursorAuth/accessToken` in
`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.

### Official or unofficial
**Unofficial.** Cursor publishes no usage API and no CLI that reports quota — `cursor
--status` prints process diagnostics (CPU, memory, PIDs) and nothing about entitlement.

### The line this adapter does not cross
Cursor's dashboard endpoints under `cursor.com/api/*` authenticate with a
`WorkosCursorSessionToken` browser cookie. Comparable tools obtain it by reading Safari and
Chrome cookie jars, or by synthesizing the cookie from the local JWT. **This adapter does
neither.** Harvesting browser cookies is the authenticated-session scraping the project
rules prohibit outright, and forging a session cookie impersonates a browser the service
never issued one to.

Presenting Cursor's own token to Cursor's own API is a different act — the same credential
the editor uses, for the same purpose, over the same transport. The rule: **reuse the
client's credential as a client; never reconstruct the browser's.**

That line was tested rather than assumed. With a bearer token:

```
https://api2.cursor.sh/auth/usage      →  200
https://cursor.com/api/usage-summary   →  401   (bearer not accepted)
https://cursor.com/api/auth/me         →  200, empty body
```

The richer usage-based-pricing figures are genuinely unreachable without the cookie. That
is a measured result, not a guess — `SIDENOTCH_PROBE_SCHEMA=1 swift run usage-probe`
reproduces it.

### Reading a 4.9 GB database another process owns
Read-only, one `SELECT` of one row by exact key. `mode=ro` first, so the write-ahead log is
respected and the token is current; on failure it retries with `immutable=1`, which cannot
contend at all but may predate the WAL. A stale token is recoverable (401 → unavailable);
blocking Cursor's own writes is not. Busy timeout is 250 ms.

### Fields obtained
Per model bucket: `numRequests`, `maxRequestUsage`. Plus `startOfMonth`, from which the
reset is computed as one **calendar** month later — not +30 days, which lands on the wrong
day in a 31-day month.

### Refresh
Same mechanism as Claude, floored at 120 seconds. Cursor has not been observed
rate-limiting this endpoint; the floor exists so a hover-storm cannot become a request
storm against any provider.

### Caching / failure behaviour / drift protection
Identical in structure to Claude's. `CursorUsageDecoder` throws when no recognised bucket
is present, naming the keys it saw.

### Security
- Only the access token is read. `cursorAuth/refreshToken` sits in the same table and is
  deliberately never touched.
- JWT `exp` is parsed without signature verification — we are not authenticating the token,
  only deciding whether it is worth a request. A malformed token yields "expiry unknown",
  which is treated as usable, not as expired.
- Same `Secret` handling and ephemeral session as Claude. No cookie header is ever set,
  and a test asserts that.

### Known limitations
1. **The bearer endpoint describes the legacy request pool.** On an account using
   usage-based pricing every ceiling is `null`, so there is no percentage to show. The
   adapter reports `.unavailable` with "No metered quota" rather than a blank ring — the
   read succeeded, there is simply nothing metered. **This is the state on this machine.**
2. Dollar-denominated usage-based-pricing figures are out of reach by the cookie decision
   above. A partial honest reading beats a complete dishonest one.
3. Schema is taken from several independent extensions plus one live 200 response. Less
   corroborated than Claude's.

---

## Cross-cutting guarantees

Every one of these is enforced by a test in `ProviderKitTests`:

| Guarantee | Where |
|---|---|
| A secret cannot be printed or encoded | `SecretTests` |
| The token never reaches a user-facing field | `tokenNeverSurfaces` |
| No cookie is ever sent to Cursor | `requestHeaders` |
| A drifted schema fails closed, never a zeroed ring | `driftFailsClosed` (both) |
| An unmetered bucket gets no invented denominator | `unmeteredHasNoFraction` |
| A refused read costs no request | `throttledReadMakesNoRequest` |
| A 401 does not trigger a refresh | `unauthorizedDoesNotRefresh` |
| Absence of data surfaces as absence | `unreadableProvidersHaveNoFigures` |
| A stale stored expiry does not block the attempt | `staleExpiryStillAttempts` |

No test opens a socket or touches the real keychain; both are injected seams. The suite
runs in ~0.02s.

## Diagnostics

`swift run usage-probe` prints each provider's live state, and now the *reason* when there
are no figures, plus `credentialSource`, `storedExpiry`, and any unrecognised schema keys.
`SIDENOTCH_PROBE_SCHEMA=1` additionally dumps candidate endpoint response shapes — key
names and numeric values only, strings reduced to their type.
