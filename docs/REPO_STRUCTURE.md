# Repository Structure

```text
SideNotch/
├── apps/
│   ├── SideNotchMac/
│   │   ├── App/
│   │   ├── Views/
│   │   ├── Windows/
│   │   ├── Services/
│   │   ├── Resources/
│   │   └── SideNotchMac.xcodeproj
│   │
│   └── SideNotchIOS/
│       ├── App/
│       ├── Views/
│       ├── Widgets/
│       ├── LiveActivity/
│       └── SideNotchIOS.xcodeproj
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
