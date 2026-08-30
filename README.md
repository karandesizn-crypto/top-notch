# Top Notch — Product + Engineering Scaffold

A local-first macOS utility for glanceable AI coding-tool usage, with an iOS companion.

## Product promise
See your AI coding limits and reset times without leaving your workflow.

## V1 providers
- Claude
- Cursor
- Codex

## Platforms
- macOS: primary product
- iOS: companion app + widgets/Live Activity where appropriate

## Architecture principle
Local-first. Provider credentials stay on-device in Keychain. The optional backend stores account/app metadata and sync preferences, not raw provider credentials.

## Build order
1. Mac shell + side rail
2. Provider model + mock data
3. Expansion/detail interaction
4. Notifications + reset calculations
5. Real provider adapters
6. iOS companion
7. Optional backend sync
8. Packaging, signing, telemetry/privacy controls
