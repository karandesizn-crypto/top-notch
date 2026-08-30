# Architecture

```text
                 ┌─────────────────────────────┐
                 │        Top Notch Mac        │
                 │  Side rail / detail card   │
                 └──────────────┬──────────────┘
                                │
                         Shared state
                                │
        ┌───────────────────────┴────────────────────────┐
        │                                                │
┌───────▼────────┐                             ┌─────────▼─────────┐
│ SideNotchCore  │                             │   ProviderKit     │
│ domain/models  │                             │ adapter protocol  │
│ calculations    │                             │ integrations      │
└───────┬────────┘                             └─────────┬─────────┘
        │                                                │
        ├── SwiftData                                   ├── Claude
        ├── Keychain                                    ├── Cursor
        └── App Groups                                   └── Codex
        │
┌───────▼─────────┐
│ NotificationSvc │
│ alerts/reset    │
└─────────────────┘

                  optional cloud layer
                         │
                ┌────────▼─────────┐
                │     Supabase     │
                │ Auth + DB + jobs │
                └────────┬─────────┘
                         │
                 sync/entitlements
                         │
      ┌──────────────────▼──────────────────┐
      │             iOS companion           │
      │ SwiftUI + WidgetKit + ActivityKit  │
      └─────────────────────────────────────┘
```

## Important boundary
Provider access is isolated behind `UsageProvider`.
The UI never knows how Claude/Cursor/Codex data is obtained.

## Provider status
Each adapter returns a normalized `UsageSnapshot`:

- provider
- current session usage
- all-model / weekly usage when available
- remaining amount when derivable
- reset date
- confidence/source metadata
- last updated date
- availability/error state

Never fabricate a value when the provider does not expose it.
