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
| **Claude** | `api.anthropic.com/api/oauth/usage` + Keychain token | **Unofficial** | ✅ Session 52%, Weekly 37%, plan pro | **Medium** |
| **Cursor** | `DashboardService/GetCurrentPeriodUsage` (Connect RPC) + `state.vscdb` token | **Unofficial** | ✅ real percentage returned | **Medium** |

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
1. **Undocumented endpoint.** Assume it will break. The decoder fails closed when it does.
2. **We cannot renew a lapsed token** — by design. When Claude Code's *persisted* access
   token expires, usage is unavailable until Claude Code writes a fresh one. Observed to sit
   stale for ~19 hours; see the remediation below.
3. **The endpoint rate-limits hard and recovers slowly.** Six probe runs in a few minutes
   earned a `rate_limit_error` that persisted across roughly an hour, with no `Retry-After`.
   In normal operation the 180-second floor keeps well clear of this; it is a hazard for
   development, not for use.
4. Org-managed accounts may mint tokens without `user:profile`; those report unsupported.
5. Only `five_hour` and `seven_day` were returned on this Pro account. The
   `seven_day_opus` / `seven_day_sonnet` windows are decoded when present and simply absent
   here — the adapter never assumes a fixed set.

---

## Cursor

### Data source
`POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`, spoken
over **Connect RPC** (POST-only even for reads, empty body,
`Connect-Protocol-Version: 1`), bearer-authenticated with the token from
`cursorAuth/accessToken` in
`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.

`GET https://api2.cursor.sh/auth/usage` remains as a fallback for older accounts still
governed by a request quota. It is tried only when the dashboard call fails, so the normal
path is one request.

**This endpoint came from reading `zchan0/MyUsage`.** The first implementation used only
`/auth/usage`, which answers 200 on a modern account with every ceiling `null` — no
percentage exists, so Cursor showed "No metered quota". The dashboard service returns a
real `totalPercentUsed`, the included allowance in cents, and the billing cycle, on the
same bearer token, with no cookie. Verified live: Cursor went from no reading at all to
"Included usage — 0% — Resets Sep 29".

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

### "No metered quota" is not a failure
Both a successful-but-empty read and an integration failure leave the rail with nothing to
draw, so the difference is carried in the state rather than only in the wording:

| | successful, nothing metered | integration failure |
|---|---|---|
| `status` | `.unavailable` | `.unavailable` |
| `failure` | "No metered quota" | "Sign in to Cursor", "Rate limited", … |
| `metadata["outcome"]` | `noMeteredQuota` | absent |
| `metadata["readSucceeded"]` | `"true"` | absent |
| `lastUpdated` | set | set |

`status` stays `.unavailable` because there is genuinely no measurement to draw — that is
what the rail needs to know, and it keeps the locked visual treatment unchanged.

This distinction has a consequence beyond labelling. `UsageManager` normally re-serves the
last good figures as `.cached` when a retryable failure arrives, so a blip does not blank a
number the user was reading. A successful read that found nothing must **not** be papered
over that way — it would show a percentage the account no longer has. So a read marked
`readSucceeded` always wins over the cache.

### Known limitations
1. **The legacy fallback describes a request pool that modern accounts do not use.** When
   the dashboard call fails and the fallback answers, every ceiling on a usage-based account
   is `null`, so no percentage exists and the adapter reports "No metered quota". That is
   the read succeeding and finding nothing metered — not a fault.
2. **A zero allowance is still reported as no metered quota**, not as a 0% ring. A
   percentage with no allowance behind it describes nothing.
3. The response carries display copy, a 28-entry model list and threshold hints that are
   deliberately ignored; only `planUsage` and the billing cycle are consumed.
4. Undocumented and unversioned. Schema is corroborated by one reference implementation plus
   live responses from this account.

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
| "No metered quota" is distinguishable from a failure | `noQuotaIsNotAFailure` |
| A successful empty read is not masked by the cache | `authoritativeEmptyReadClearsFigures` |
| A signed-out Cursor reads as signed out, not broken | `signedOutDatabase` |
| A stale keychain item does not win over a fresh one | `picksFreshest` |
| A stale stored expiry does not block the attempt | `staleExpiryStillAttempts` |

No test opens a socket or touches the real keychain; both are injected seams. The suite
runs in ~0.02s.

## Reference implementations

Three comparable open-source projects were read and compared against this implementation:
[`steipete/CodexBar`](https://github.com/steipete/CodexBar),
[`zchan0/MyUsage`](https://github.com/zchan0/MyUsage), and
[`fdtorres1/AgentMeter`](https://github.com/fdtorres1/AgentMeter).

### Adopted

**Cursor's Connect RPC dashboard endpoint** (from MyUsage). Detailed above. This is the
single largest improvement in the integration: Cursor went from reporting nothing to
reporting a real percentage, without moving the cookie boundary an inch. The reference
supplied the endpoint name and the `Connect-Protocol-Version` header; the DTOs, validation,
drift detection, and no-metered-quota handling are ours.

**Reading both credential stores rather than the first that answers** (from MyUsage, which
reads `~/.claude/.credentials.json` before the keychain). The original implementation
short-circuited on a successful keychain read. That looks reasonable and is subtly wrong:
the two stores can disagree, and Claude Code writes to whichever its install uses while
leaving the other frozen. A stale keychain item could therefore shadow a working file and
produce a lapsed-sign-in report with a good credential on disk beside it. Both are now read
and ranked. Rather than adopting the reference's fixed order, the existing `best(of:)`
ranking was extended over the union — order-independence is the more robust property.

### Evaluated and declined

**Delegated token refresh** (MyUsage's `ClaudeDelegatedRefresh`). This solves precisely the
blocker documented below: when Claude Code's persisted token has lapsed, it spawns the
`claude` CLI on a pseudo-terminal so that *Claude Code itself* rotates the keychain
credential, then re-reads it. The reasoning is sound and matches this project's own rule —
never refresh the token ourselves, because that is what revokes the user's CLI session.

It is not adopted, for reasons of implementation rather than principle. It drives another
application's CLI through a PTY, periodically injecting Enter keypresses to dismiss any
prompt, with an 8-second timeout and a 5-minute cooldown. That is a lot of moving parts to
add to a production app for a condition the user resolves with one command — and it cannot
be verified from here, so it would ship untested. Spawning a vendor CLI on a timer is also
a side effect a usage monitor should not have by default.

If the stale-token case turns out to be common rather than incidental, this is the right
shape for the fix, and it should arrive opt-in and off by default.

**Cursor token refresh via `/oauth/token`** (MyUsage). Rejected outright: same
refresh-token rotation hazard as Claude's, against the rule that this app never renews a
credential it did not issue.

**Shelling out to `/usr/bin/security`** as a keychain fallback (MyUsage). Not needed — the
`SecItemCopyMatching` path works on this machine once `kSecMatchLimitAll` is paired with
`kSecReturnAttributes`. Worth revisiting only if ACL denials show up in the field.

### Already aligned

AgentMeter's `CredentialAssessment` makes a point worth recording: a failed verification
must not cause a stored credential to be discarded, because a transient network failure is
indistinguishable from an invalid key at the moment it happens. This implementation never
stores a credential at all, so the hazard cannot arise — but the same instinct is why a 401
here reports and waits rather than treating the credential as dead.

## Live verification status

| Provider | Status | Evidence |
|---|---|---|
| **Codex** | ✅ **Verified** | 30-day window, 0% used, plan "go", reset Sep 29 — re-confirmed after all Phase 4 refactoring |
| **Cursor** | ✅ **Verified** | Dashboard RPC returns a real reading: "Included usage — 0% — Resets Sep 29" |
| **Claude** | ✅ **Verified** | Session 52% (resets in 3h 50m), Weekly 37% (resets Thursday), plan `pro` |

### How the Claude blocker was resolved

The stored access token had lapsed at `2026-08-29T16:44:53Z` and Claude Code had not
rewritten it in ~19 hours of use. `claude auth status` reported `loggedIn: true` throughout
— the *login* was healthy, only the persisted token was stale — and `claude auth status`
does not itself trigger a refresh.

The fix was to let Claude Code refresh its own credential, which is the same principle as
MyUsage's delegated refresh but without the PTY automation that made that version
unattractive:

```
claude -p "…" --no-session-persistence --max-budget-usd 0.50
```

`-p` is the documented non-interactive mode. Making any API call forces Claude Code to
refresh its OAuth token and rewrite the keychain item, after which this adapter — which
re-reads the credential on every fetch — picks up the new value with no coordination.
Verified: stored expiry moved to `2026-08-30T18:48:19Z`, and the endpoint returned 200.

Two things worth recording for next time:

- **`--max-budget-usd 0.01` is refused before the call is made.** The budget is checked
  against an estimated ceiling, not actual spend, so too tight a cap fails closed and
  refreshes nothing.
- **Nothing in SideNotch does this.** It remains a manual remediation. Spawning a vendor
  CLI on a timer is a side effect a usage monitor should not have, and the adapter's rule —
  never renew a credential it did not issue — is what keeps it from revoking the user's CLI
  session.

If the token lapses again, either that command or `claude auth login` restores it, and the
next poll recovers on its own.

## Diagnostics

`swift run usage-probe` prints each provider's live state, and now the *reason* when there
are no figures, plus `credentialSource`, `storedExpiry`, and any unrecognised schema keys.
`SIDENOTCH_PROBE_SCHEMA=1` additionally dumps candidate endpoint response shapes — key
names and numeric values only, strings reduced to their type.
