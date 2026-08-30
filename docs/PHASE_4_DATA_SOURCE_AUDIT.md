# Phase 4 — Data Source Audit

> **⚠️ Superseded for Claude and Cursor.** This audit concluded both were unsupported. That
> conclusion tested the wrong question — "is there a documented API?" rather than "is there
> a safe, reproducible mechanism?" — and both now have working adapters. See
> `PROVIDER_INTEGRATIONS.md`. The Codex findings and the security sweep below still stand,
> and the evidence here for *why the documented routes do not work* remains accurate and is
> still the reason the integrations had to be unofficial.

**Date:** 2026-08-30
**Scope:** Every provider Top Notch ships or could ship. What data exists, whether it can
be read legitimately, and whether it is safe to ship.

Findings are from direct inspection of this machine and of Anthropic's published API
documentation. Nothing here is inferred from memory.

---

## Verdict table

| Provider | Data source | Reliability | Production safe | Decision |
|---|---|---|---|---|
| **Codex** | `codex app-server` JSON-RPC over child-process stdio: `account/rateLimits/read`, `account/rateLimits/updated`, `account/usage/read` | **High** — live, push-updated, schema-declared. Risk is version drift, not correctness | **Yes** — local subprocess, no network, no credentials | ✅ **Implement** (shipped; add a drift guard) |
| **Claude Code** | None viable. CLI exposes no usage command; `~/.claude.json` holds a stale cache; the live route is an undocumented OAuth endpoint | **None** | **No** | ❌ **Unsupported** |
| **Cursor** | None. Usage is server-side; `state.vscdb` holds no quota data | **None** | **No** | ❌ **Unsupported** |
| **Custom** | User-declared command returning the documented JSON contract | Depends on the user's command | **Yes** — explicit, user-authored, no ambient credentials | ✅ **Implement** (shipped) |

---

## Codex — Implement

**Mechanism.** Top Notch spawns `codex app-server` as a child process and speaks JSON-RPC
over its stdio. It reads `account/rateLimits/read` on demand and subscribes to
`account/rateLimits/updated` for push updates.

**Why this is the right tier.** Per the integration preference order, this is tier 2 —
an official CLI surface — not a scraped or reverse-engineered one. The binary generates
its own protocol schema, which is what a supported binding surface looks like.

**Evidence.**

```
$ /Applications/Codex.app/Contents/Resources/codex --version
codex-cli 0.147.0-alpha.1.2

$ codex app-server generate-json-schema --out schema
$ grep -rhoE '"account/(rateLimits|usage)/[a-zA-Z]+"' schema | sort -u
"account/rateLimits/read"
"account/rateLimits/updated"
"account/usage/read"
```

Field-level drift check against `v2/GetAccountRateLimitsResponse.json` (29 fields):

```
in schema but NOT in our DTOs: (none)
```

Every field the current schema declares is covered. The nine extra fields in our DTOs
(`dailyUsageBuckets`, `lifetimeTokens`, `peakDailyTokens`, …) belong to
`account/usage/read`, the sibling endpoint — expected, not drift.

**Credentials.** None handled. `~/.codex/auth.json` is `fileExists`-checked only and never
opened; the app-server owns the session. Verified:

```
CodexInstallation.swift:41: fileManager.fileExists(atPath: ...appendingPathComponent("auth.json").path)
```

**The real risk — and it is not correctness.** Both the CLI and the interface are
pre-release:

```
$ codex --help
  app-server      [experimental] Run the app server or related tooling
```

An `[experimental]` subcommand on an `-alpha` build can change field names or method names
without notice. Today's zero-drift result is a snapshot, not a guarantee.

**Recommended mitigation (Phase 5 work, not done yet):**

1. **Version-pinned drift guard.** Record the `codex --version` string alongside the
   cached snapshot. On a version change, re-probe before trusting the mapping.
2. **Fail to `unavailable`, never to wrong figures.** A decode failure must surface as
   "Codex data unreadable", not a stale or partial ring. The `UsageState.failed` path
   already does this; the guard needs to route into it explicitly.
3. **Re-verify on every Codex update** as a release checklist item.

---

## Claude Code — Unsupported

Three routes were examined. All three fail.

### Route 1 — CLI command. Does not exist.

```
$ claude --version
2.1.83 (Claude Code)

$ claude --help    # subcommands:
agents, auth, auto-mode, doctor, install, mcp, plugin, setup-token, update
```

No usage, limit, or quota subcommand. No app-server, no daemon, no local IPC surface
equivalent to Codex's.

### Route 2 — Local cache. Present but unusable.

`~/.claude.json` carries a `cachedUsageUtilization` object. Measured:

```
fetchedAtMs = 1786963498319  ->  299.0 hours old
```

**299 hours is 12.5 days.** The value did not advance between two checks on separate days,
confirming it refreshes only when Claude Code itself fetches — it is a cache of a past
fetch, not a live feed. Presenting it as current usage would violate the rule against
showing fake "live" values, and `StalenessPolicy` would correctly reject it anyway.

### Route 3 — Documented Anthropic APIs. Wrong product, wrong shape.

Two published endpoints touch usage. Neither fits:

| Endpoint | Why it doesn't work |
|---|---|
| `GET /v1/organizations/usage_report/messages` | Reports **API token consumption** for an organization. Says nothing about Claude Code subscription windows. |
| `GET /v1/organizations/usage_report/claude_code` | Claude Code Analytics: **daily aggregated** sessions, lines of code, commits, estimated cost. Contains **no** limit, quota, remaining, percent, reset, or window field. |

Both are Admin API endpoints, and the documentation is explicit:

> "The Admin API is unavailable for individual accounts."

They require an Admin API key or `org:admin` OAuth token, are organization-scoped, and
report *activity*, not *headroom*. Even for an enterprise user with an admin key, the
data has the wrong shape for a live limit ring.

### The route the rules exclude

The only surface returning live Claude Code limit percentages is
`api.anthropic.com/api/oauth/usage`, called with the OAuth token from the login keychain
entry. This is excluded on three independent grounds:

1. It is **undocumented** — §7 forbids depending on undocumented private endpoints as the
   primary architecture.
2. It requires **extracting an authentication token** the user did not hand us — §7
   forbids this explicitly.
3. It carries a real **account-safety hazard**: as recorded in `docs/PRIOR_ART.md`,
   third-party tools calling this endpoint with a borrowed token have triggered
   token-family revocation, logging the user out of Claude Code.

**Decision: `unsupported`.** Top Notch shows "No local usage API yet" and no figures.
This is the outcome §7 prescribes: *if a provider does not expose a reliable integration
method, do not fake it.*

**What would change this:** an official `claude usage` command, or a documented
subscription-limits endpoint reachable with a user-authorized credential. Both are
provider-side changes. The `ClaudeUsageProvider` adapter is already in place and would
need only its fetch path filled in.

---

## Cursor — Unsupported

**No CLI surface.** `/Applications/Cursor.app/Contents/Resources/app/bin/cursor --status`
prints process diagnostics — CPU, memory, PIDs — not quota.

**No local quota data.** A full sweep of `state.vscdb` `ItemTable` found no usage figures.
Two keys looked promising and both were dead ends on inspection:

| Key | Actual content | Verdict |
|---|---|---|
| `cursor.slashUsage.v1` | `{"schemaVersion":1,"entries":{"slash:v1:[\"skill\",…]":{"counters":{"selected":1}}}}` | Slash-command **telemetry** — how often each command was picked. Misleading name; contains no quota. |
| `cursorAuth/stripeSubscriptionStatus` | `"active"` | Subscription **state**, not headroom. No figures. Sits in an auth namespace. |

Remaining `cursor.*` keys are UI, banner, and plugin state.

Cursor usage is server-side and reachable only by replaying an authenticated session —
exactly the cookie/session scraping §7 prohibits.

**Decision: `unsupported`.** Shows "Not exposed outside Cursor".

---

## Security invariants — re-verified this phase

Swept across `packages/`, `apps/`, and `tools/`:

| Invariant | Result |
|---|---|
| No network calls | ✅ No `URLSession`, `CFNetwork`, or socket use anywhere. The single `https://` match is a comment. |
| No keychain access | ✅ No `SecItem`, `kSec`, or Keychain API use. |
| No cookie or token reads | ✅ No `NSHTTPCookie`, no token extraction. |
| `auth.json` never opened | ✅ `fileExists` only. |
| No credential logging | ✅ `Log.swift` documents the prohibition; no call site passes secrets. |

---

## Summary

One provider ships with real data. Two ship honestly empty. That ratio is the correct
outcome of the rules, not a shortfall against them — the alternative for Claude and Cursor
is fabrication or token theft, and both are out of bounds.

The one item needing a decision is the **Codex alpha/experimental exposure**: real data
today, on an interface that carries no stability promise.
