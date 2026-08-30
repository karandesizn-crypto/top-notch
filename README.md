# Top Notch

A macOS utility that shows your AI coding-tool usage in the camera notch, so you stop
context-switching to find out whether Claude, Codex, or Cursor is about to cut you off.

Currently a **personal alpha**: it runs on one Mac, unsigned, with all three integrations
live. See [`docs/LOCAL_ALPHA.md`](docs/LOCAL_ALPHA.md).

```
./scripts/dev-install.sh
```

## Providers

| Provider | Source | Official | Reads |
|---|---|---|---|
| **Codex** | `codex app-server` JSON-RPC over stdio | ✅ official CLI surface | 30-day window, plan, credits |
| **Claude** | `api.anthropic.com/api/oauth/usage` | ⚠️ undocumented | 5-hour session, weekly, plan |
| **Cursor** | `DashboardService/GetCurrentPeriodUsage` (Connect RPC) | ⚠️ undocumented | Billing-period usage, allowance |

Two of the three are undocumented vendor endpoints and may break without notice. They
**fail closed**: a schema that moves produces "unavailable", never a wrong number.

Details, including what was rejected and why:
[`docs/PROVIDER_INTEGRATIONS.md`](docs/PROVIDER_INTEGRATIONS.md).

## The rules this is built to

- **Never fabricate a figure.** No estimates, no guessed denominators, no stale reading
  presented as current. Absence of data surfaces as absence.
- **Reuse the login you already have; never renew it.** The app reads Claude Code's and
  Cursor's own credentials and cannot refresh either — refreshing would rotate a token
  family and sign you out of your own CLI.
- **Never harvest a browser session.** Cursor's richer dashboard figures are reachable by
  forging a session cookie. They are not taken. The line: reuse the client's credential as
  a client, never reconstruct the browser's.
- **No telemetry, no analytics, no account.** Nothing leaves the machine except
  authenticated requests to your own providers.

## Layout

```
apps/SideNotchMac/     macOS app — UI and wiring only
packages/
  SideNotchCore/       pure domain: usage state, levels, thresholds, resets
  NotchKit/            notch geometry and surface layout, pure math
  ProviderKit/         provider adapters, credentials, HTTP, rate limiting
  UsageKit/            app logic: manager, scheduler, cache, settings
tools/usage-probe/     CLI that prints live provider state
scripts/
  dev-install.sh       build + install locally (the one you want)
  release.sh           signed/notarized distribution (parked)
  validate-release.sh  release checks
```

Module names still read `SideNotch` — internal identifiers, kept because 44 files import
them and renaming buys nothing a user can see.

**209 tests**, none of which open a socket or touch the real keychain.

## The design lock

The notch UI is fixed. Every change since is verified against golden renders of four states
(rest, hover, pinned, mini), compared by hash against the commit before the provider work
began. They have been byte-identical throughout.

## Docs

| | |
|---|---|
| [`LOCAL_ALPHA.md`](docs/LOCAL_ALPHA.md) | Running it on your own Mac |
| [`PROVIDER_INTEGRATIONS.md`](docs/PROVIDER_INTEGRATIONS.md) | What each adapter does, and how far to trust it |
| [`PHASE_4_DATA_SOURCE_AUDIT.md`](docs/PHASE_4_DATA_SOURCE_AUDIT.md) | Why the documented APIs do not work |
| [`RELEASE.md`](docs/RELEASE.md) | Public distribution — parked |
| [`CODEX_INTEGRATION.md`](docs/CODEX_INTEGRATION.md) | The Codex app-server protocol |
| [`PROVIDER_MARKS.md`](docs/PROVIDER_MARKS.md) | Trademark question, unresolved |
| [`MAC_UX.md`](docs/MAC_UX.md) · [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Interaction and structure |

## Known limitations

- Claude and Cursor depend on undocumented endpoints.
- Codex's `app-server` is `[experimental]` on an alpha CLI.
- A lapsed Claude token needs `claude auth login`; the app will not renew it.
- Unsigned: it runs on the machine that built it, and nowhere else.
- No app icon yet.
