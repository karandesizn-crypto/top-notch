# Tech Stack

## Frontend — macOS
- Swift 6+
- SwiftUI for primary UI
- AppKit where SwiftUI is insufficient for floating/edge-attached behavior, window levels, event monitoring, and screen geometry
- MenuBarExtra for menu-bar presence/settings entry
- Observation / @Observable for app state
- Swift Concurrency (async/await, actors, AsyncSequence)
- Core Animation / NSVisualEffectView only where needed for visual polish
- Swift Package Manager for modular code

## Frontend — iOS
- Swift 6+
- SwiftUI
- WidgetKit for Home Screen / Lock Screen / widget surfaces
- ActivityKit for Live Activities / Dynamic Island
- UserNotifications for threshold alerts
- App Intents later for shortcuts and interactive actions

## Shared app code
- SideNotchCore: domain models, usage calculations, reset timers, provider state, app settings
- ProviderKit: provider adapter protocol + provider-specific implementations
- Shared design tokens and formatting utilities

## Local storage
- SwiftData for app-owned structured state
- Keychain Services for provider credentials/tokens/secrets
- App Groups to share state between app and widgets/extensions where required

## Networking
- URLSession
- Codable DTOs
- URLSessionWebSocketTask only if a provider integration ever needs streaming updates

## Backend — optional / V1.5
- Supabase
  - Postgres: account profile, sync preferences, entitlements, optional aggregated history
  - Auth: Sign in with Apple
  - Edge Functions: server-side jobs that never expose provider credentials to the client unless a provider explicitly requires a server-side flow
  - Realtime: optional sync channel

## Observability
- OSLog for local diagnostics
- MetricKit later for production performance/crash diagnostics
- No analytics in V1 unless explicitly consented to

## Payments
- StoreKit 2 for Mac App Store / iOS App Store subscriptions or one-time purchase
- Avoid creating a custom billing backend unless product pricing requires it

## CI/CD
- Xcode Cloud or GitHub Actions + xcodebuild
- Fastlane only if signing/release automation becomes complex

## Testing
- Swift Testing for unit tests
- XCTest / UI tests where needed
- Mock provider adapters for deterministic tests

## Design
- Figma for product/design system
- SF Symbols where possible
- Custom provider marks only where licensing/branding rules allow
