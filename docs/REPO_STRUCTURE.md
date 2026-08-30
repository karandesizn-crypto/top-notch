# Repository Structure

```text
Top Notch/
├── apps/
│   ├── SideNotchMac/
│   │   ├── App/
│   │   ├── Views/
│   │   ├── Windows/
│   │   ├── Services/
│   │   ├── Resources/
│   │   └── SideNotchMac.xcodeproj
│   │
│   └── Top NotchIOS/
│       ├── App/
│       ├── Views/
│       ├── Widgets/
│       ├── LiveActivity/
│       └── Top NotchIOS.xcodeproj
│
├── packages/
│   ├── SideNotchCore/
│   │   ├── Models/
│   │   ├── Logic/
│   │   ├── Formatting/
│   │   └── Persistence/
│   │
│   └── ProviderKit/
│       ├── Protocols/
│       ├── Claude/
│       ├── Cursor/
│       ├── Codex/
│       └── Mocks/
│
├── backend/
│   └── supabase/
│       ├── migrations/
│       └── functions/
│
├── docs/
├── shared/
├── tools/
└── README.md
```

## Dependency direction
UI → Core + ProviderKit
Provider adapters → Core models
Core → no UI dependency
Backend → independent of provider credentials
