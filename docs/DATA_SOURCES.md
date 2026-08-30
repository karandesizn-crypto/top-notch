# Provider Data Sources

What each provider actually exposes on a local machine, verified by read-only probe on
2026-08-29 (macOS 27, Claude Code 2.1.247, Codex CLI, Cursor 3.18).

This file exists because the answer is not uniform, and the differences drive real product
decisions. Re-verify after any provider's major version bump.

---

## Claude — `~/.claude.json` → `cachedUsageUtilization`

**Status: complete.** Percentages, reset times, and multiple windows.

Claude Code caches the server's usage response into `~/.claude.json`. The `utilization`
object carries per-window keys (`five_hour`, `seven_day`, plus several internal codenames)
and — more usefully — a normalized `limits` array:

```json
{
  "fetchedAtMs": 1786963498319,
  "utilization": {
    "limits": [
      { "kind": "session",    "group": "session", "percent": 50,
        "resets_at": "2026-08-17T10:50:00.173972+00:00", "is_active": true  },
      { "kind": "weekly_all", "group": "weekly",  "percent": 13,
        "resets_at": "2026-08-19T19:00:00.173995+00:00", "is_active": false }
    ]
  }
}
```

`ClaudeProvider` parses `limits[]`, **not** the individual `five_hour` / `seven_day` keys.
The sibling keys include internal codenames (`nimbus_quill`, `tangelo`, `iguana_necktie`,
…) that are clearly experiment-scoped and will churn; `limits[]` is the stable, generic
shape and new limit kinds surface through it automatically.

Two caveats:

- **The cache is only as fresh as Claude Code's last fetch.** `fetchedAtMs` is used
  verbatim as `observedAt`; on the probe machine it was 11 days old. `StalenessPolicy`
  governs presentation. The adapter never freshens or back-dates a reading.
- **The file also holds OAuth and account material.** `ClaudeProvider` decodes exactly one
  key into a narrow `Decodable` and never logs the raw file. See SECURITY.md.

### Rejected alternative: transcript `quotaLimits`

Session transcripts (`~/.claude/projects/**/*.jsonl`) carry a `quotaLimits` object:

```json
{ "status": "rejected", "resetsAt": 1787268600, "rateLimitType": "five_hour",
  "overageStatus": "rejected", "isUsingOverage": false }
```

It appeared **once across 7 transcript files**, on an `assistant` line, at the moment a
limit was actually hit. It is a rejection event, not a feed, and carries no percentage.
Not used. Per-message `message.usage` token counts are continuous but have no denominator,
so they cannot yield a percentage without inventing one.

---

## Codex — app-server (superseded the log-parsing approach)

**Status: shipped, live.** See `docs/CODEX_INTEGRATION.md` for the full contract.

Top Notch now reads Codex through its **app-server** — the supported local JSON-RPC
interface — calling `account/rateLimits/read` and subscribing to
`account/rateLimits/updated`. That is strictly better than parsing rollout logs: it is a
supported surface rather than an implementation detail, it returns the current value rather
than the last one a session happened to write, and it pushes updates.

The log-parsing approach below is retained only as background on how the shape was first
discovered. **It is no longer used**, and its field names differ — the logs are snake_case
(`used_percent`, `window_minutes`), the app-server is camelCase (`usedPercent`,
`windowDurationMins`).

### Former approach — session rollout logs (not used)

Codex writes a `token_count` event on each turn:

```json
{"type":"event_msg","payload":{"type":"token_count","rate_limits":{
  "primary":   {"used_percent":35.0,"window_minutes":43200,"resets_at":1788530189},
  "secondary": null,
  "plan_type":"go",
  "credits":{"has_credits":false,"unlimited":false,"balance":null}}}}
```

`window_minutes` identifies the window (43200 = 30 days, 300 = 5 hours), so scope is
derived rather than assumed. `primary` and `secondary` each become their own snapshot.

`CodexProvider` finds the newest rollout by modification time and scans it **backwards**
(`TailScanner`) for the last `rate_limits` event — these files grow without bound and the
current reading is always near the end.

---

## Cursor — no local data

**Status: unavailable.** Not a parsing problem; the data is not on disk.

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (4.9 GB) was queried
across both `ItemTable` and `cursorDiskKV` for `%usage%`, `%quota%`, `%limit%`, and
`%subscription%`. Zero usage rows. The only matches were cached *file contents* whose
filenames happened to contain those words. Cursor fetches its usage figures from its
servers per session and does not persist them.

The only known mechanism is replaying Cursor's private endpoints with the user's session
cookie. That is ruled out by SECURITY.md ("do not upload browser cookies/session cookies")
and by the Phase 4 rule in CLAUDE_CODE_BUILD_PLAN.md ("never scrape or reverse-engineer
private endpoints as a default architecture").

So `CursorProvider` returns an explicit `.unavailable` snapshot with a reason string. It
stays visible in the rail rather than being hidden: DOMAIN_MODEL.md forbids fabricating a
value the provider does not expose, and a visible "unavailable" is more honest — and more
useful — than a provider that silently disappears.

**Open path:** if Cursor ships a documented usage API, or a supported CLI that prints
quota, the adapter becomes a drop-in replacement behind `UsageProvider`. Nothing else in
the app changes.

---

## Consequence for build order

CLAUDE_CODE_BUILD_PLAN.md Phase 4 sequences adapters Claude → Cursor → Codex. Actual
difficulty runs the other way: **Codex → Claude → Cursor**, and Cursor is blocked on the
provider rather than on us.
