# Prior Art

Three repos reviewed 2026-08-29. All MIT licensed.

| Repo | Stars | Last push | What it is |
|---|---|---|---|
| [ericjypark/codex-island](https://github.com/ericjypark/codex-island) | 310 | 2026-08-18 | **This product, already shipped.** |
| [govijr/DynamicNotch-MacOS](https://github.com/govijr/DynamicNotch-MacOS) | 15 | 2026-08-19 | Reusable notch-surface SwiftUI package |
| [omerates760/AgentPulse](https://github.com/omerates760/AgentPulse) | 1 | 2026-04-12 | Agent session monitor (approvals/questions) |

---

## codex-island — the competitor

"Your AI usage limits, living in your notch." Claude and Codex, 5-hour and weekly
windows, reset timing, cost estimates from local logs, year-at-a-glance history. Free,
open source, local-first, unsigned. 310 stars, 35 forks, actively maintained.

This is substantially the product in this repo's README, with a two-month head start.

### It solves our staleness problem

`docs/DATA_SOURCES.md` records that Claude's `cachedUsageUtilization` only refreshes when
Claude Code itself fetches, which made every local reading hours or days old. codex-island
sidesteps the cache entirely: it reads the OAuth credentials Claude Code already stored and
calls the provider's own usage endpoint.

- Claude: `https://api.anthropic.com/api/oauth/usage`
- Codex: `https://chatgpt.com/backend-api/wham/usage`
- Codex credits: `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`

### Hazards it documents, which we would otherwise have hit

Its `ClaudeCredentials` module is worth reading in full before we go anywhere near this
approach. Its findings, paraphrased:

1. **Never call the OAuth refresh endpoint.** Anthropic rotates `refresh_token` on every
   refresh and revokes the entire token family if an old token is reused. A second
   refresher racing Claude Code invalidates the user's CLI login. Read the token, never
   write it; if it is expired, wait for Claude Code to refresh it.
2. **The rate limiter is per account, not per token.** Retrying a 429 with a different
   token only feeds the limiter.
3. **The usage endpoint requires a `user:profile` scope** added mid-2026. A refresh
   re-issues the same scopes, so a token missing it can only be fixed by `claude /login` —
   the app has to prompt, not retry.

### Conflict with our own rules

These are private, undocumented endpoints. `CLAUDE_CODE_BUILD_PLAN.md` Phase 4 says "never
scrape or reverse-engineer private endpoints as a default architecture," and SECURITY.md
constrains credential handling. Reading a token another app stored in order to call an
undocumented endpoint is not the browser-cookie case SECURITY.md names, but it is squarely
the Phase 4 case.

Adopting it is a deliberate policy change, not an implementation detail. It also breaks
whenever a provider changes the endpoint, and may sit outside provider terms.

---

## DynamicNotch-MacOS — the useful dependency

A focused SwiftUI + AppKit package (~1,700 LOC) for edge-attached notch surfaces. It
already solves what `Windows/` and `Views/Shapes.swift` hand-roll here:

- `DynamicNotchShape` with `shoulderRadius` — the concave shoulder that took two attempts
- `DynamicNotchEdgeAlignment` / placement, including **side** edges, not just the top notch
- Safe-area and physical camera-housing handling per display
- `.clipShape(shape).contentShape(shape)` — hit testing clipped to the silhouette itself,
  which is strictly better than our rectangular `PassthroughContentView`

Caveat: created 2026-08-19, 15 stars, no forks, one author, no issue history. Too new to
take as a version-pinned dependency. It is MIT and small enough to vendor with attribution,
which gets the geometry without the supply-chain exposure.

---

## AgentPulse — skip, but note one idea

A different product: session monitoring, permission approvals, and questions surfaced at
the notch. `UsageService.swift` is a thin passthrough over whatever rate limits arrive with
a session — no independent usage source.

The idea worth stealing is its transport. Rather than polling files, it installs hooks into
Claude Code, Cursor, Codex, and Gemini that push events to a local socket server, so state
arrives in real time. If we ever want live session state rather than periodic reads, that is
the mechanism — and it needs no credentials, which keeps it on the right side of our own
security rules.
