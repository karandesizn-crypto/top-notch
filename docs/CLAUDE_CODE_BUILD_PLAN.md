# Claude Code Build Plan

Use this sequence instead of asking for the whole product at once.

## Phase 1 — Mac shell
Build:
- SwiftUI app
- menu-bar extra
- right-edge floating side rail
- per-screen placement
- click + hover states
- transparent/black visual treatment
- launch at login setting

Acceptance:
- app survives display reconnect
- rail tracks the active display edge
- no unwanted Dock icon for utility mode

## Phase 2 — Design system
Build:
- spacing tokens
- corner radii
- typography tokens
- ring component
- provider mark component
- progress bar
- detail card
- semantic usage states
- reduced-motion behavior

Use mock data only.

## Phase 3 — Core domain
Build:
- ProviderID
- UsageSnapshot
- UsageScope
- UsageHealth
- reset calculations
- stale-data policy
- threshold settings

Add unit tests before integrations.

## Phase 4 — Provider adapters
Implement one adapter at a time.
Start with Claude.
Then Cursor.
Then Codex.

Before each implementation, verify the supported/allowed data access mechanism for that provider.
Never scrape or reverse-engineer private endpoints as a default architecture.

## Phase 5 — Notifications
Build:
- 80% warning
- 90% critical
- exhausted/reset notification
- snooze
- per-provider thresholds

## Phase 6 — iOS
Build:
- companion app
- provider list
- usage detail
- WidgetKit widgets
- ActivityKit Live Activity where it materially improves glanceability

## Phase 7 — Backend
Only add sync/account backend if it solves a real product need.

## Coding rules
- Keep provider code behind protocols.
- No secrets in UserDefaults, plist, source, logs, or analytics.
- Keychain for secrets.
- Prefer structured concurrency.
- Add tests for calculations and provider normalization.
- Avoid third-party dependencies unless they solve a clear problem.

---

## Amendment — provider order

Phase 4's Claude → Cursor → Codex ordering predates the data probe. See
`docs/DATA_SOURCES.md`: the real order is **Codex → Claude → Cursor**, and Cursor has no
local data at all, so it ships as an explicit unavailable state rather than an integration.

A thin slice of Phase 4 (all three adapters + the `tools/usage-probe` CLI) was built before
Phases 1–3, so the UI is built over proven data rather than over an assumption.
