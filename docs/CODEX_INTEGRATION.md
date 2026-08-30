# Codex Integration

How Top Notch reads live Codex usage, and how that contract was established.

## What it uses

Codex's own **app-server** — the supported local integration surface its editor extensions
use. Top Notch launches `codex app-server`, speaks JSON-RPC over the child process's stdio,
and calls one method.

```
initialize                    → handshake (clientInfo: Top Notch)
initialized                   → notification
account/rateLimits/read       → GetAccountRateLimitsResponse
account/rateLimits/updated    → server notification, triggers a refresh
```

### What it deliberately does not do

- **Does not read `~/.codex/auth.json`.** Its existence is checked to distinguish "never
  signed in" from "signed in", and it is never opened, parsed, or copied.
- **Does not handle OAuth tokens.** Authentication is entirely the app-server's business.
- **Does not call `chatgpt.com` or any other provider web endpoint.**

## Establishing the contract

Method names and response shapes were not assumed. They were taken from the installed
binary:

```bash
/Applications/Codex.app/Contents/Resources/codex app-server generate-json-schema --out ./schema
```

against `codex-cli 0.147.0-alpha.1.2` (Codex.app 26.730.61639), then confirmed with a live
`account/rateLimits/read` call. `Codex/CodexRateLimitDTOs.swift` is transcribed from
`v2/GetAccountRateLimitsResponse.json`, not from one account's reply.

Note the app-server uses **camelCase** (`usedPercent`, `windowDurationMins`, `resetsAt`),
unlike the snake_case in Codex's session rollout logs. Anything written against the logs
will not decode here.

## The response

Every field inside `rateLimits` is optional in the schema, including both windows. The
account this was verified on returns a primary 30-day window and **`secondary: null`** —
so "do not assume a weekly window exists" is a real case, not a hypothetical.

```json
{
  "rateLimits": {
    "limitId": "codex",
    "primary": { "usedPercent": 0, "windowDurationMins": 43200, "resetsAt": 1790601425 },
    "secondary": null,
    "credits": { "hasCredits": false, "unlimited": false, "balance": null },
    "planType": "go",
    "individualLimit": null,
    "spendControlReached": false
  },
  "rateLimitsByLimitId": { "codex": { … } },
  "rateLimitResetCredits": { "availableCount": 1, "credits": [ … ] }
}
```

### Normalization decisions

- **`rateLimitsByLimitId["codex"]` is preferred** over the flat `rateLimits`, which the
  schema documents as a backward-compatible mirror and may not survive.
- **Window labels are derived from `windowDurationMins`**, so 300 → "5-hour",
  10080 → "Weekly", 43200 → "30-day". A window with no duration falls back to "Current
  window" rather than a guess.
- **`usedPercent` is an integer** on the wire but decoded as `Double`, so a future
  fractional value does not fail the whole response.
- **Fractions are clamped to 0...1.** `usedPercent` has no documented ceiling and an
  unclamped value would drive a ring past a full turn.
- **`individualLimit` becomes its own window.** A spend control is a real limit a user can
  hit, so it belongs beside the metered windows rather than being dropped.
- **A reply with no windows is a successful read**, not an error — the account simply has
  no metered limits.

## Process lifetime

One app-server process is held for the app's lifetime rather than spawned per refresh.
Launching Codex costs far more than a request, and a persistent connection is what makes
`account/rateLimits/updated` push notifications possible. The child is terminated on quit;
verified by checking that no `codex app-server` survives the app.

## Graceful degradation

| Condition | Result |
|---|---|
| Codex.app and CLI both absent | `.notInstalled` |
| Installed, never signed in | `.authenticationRequired` |
| App-server fails to launch or exits | `.notRunning` |
| JSON-RPC `-32601` (unknown method) | `.unsupported` — the interface moved |
| Auth wording in an error | `.authenticationRequired` |
| Anything else | `.invalidResponse` / `.unknown` |

Server error strings are never logged; they can quote request content. Only the numeric
code reaches the log, and only a fixed phrase reaches the UI.

A failure never discards the last good snapshot — the cached reading stays on the rail and
is marked stale.

## Re-verifying after a Codex update

```bash
/Applications/Codex.app/Contents/Resources/codex app-server generate-json-schema --out /tmp/codex-schema
diff <(jq -S . /tmp/codex-schema/v2/GetAccountRateLimitsResponse.json) …
```

If the schema changes shape, `CodexNormalizationTests` will keep passing against the
recorded fixtures while the live call fails — so re-record the fixtures from a real
response rather than trusting the suite alone.
