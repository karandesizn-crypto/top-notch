# Backend API Spec — Optional Sync Layer

Backend is intentionally small.

## Auth
`POST /auth/sign-in-apple`

Handled by Supabase Auth / Sign in with Apple.

## Profile
`GET /v1/me`
`PATCH /v1/me`

Stores:
- user_id
- created_at
- plan
- feature_flags

## Preferences
`GET /v1/preferences`
`PUT /v1/preferences`

Stores:
- enabled providers
- threshold preferences
- notification preferences
- appearance preferences

## Device registration
`POST /v1/devices`

Stores:
- device id
- platform
- app version
- push token when applicable

## Usage history (optional)
`POST /v1/usage-events`
`GET /v1/usage-history?provider=claude&from=...&to=...`

Only normalized, non-secret usage records should be stored.

## Entitlements
`GET /v1/entitlements`

Backend verifies purchase status when needed. StoreKit remains the source of truth on-device for transaction verification.

## Security rule
Never send provider passwords, session cookies, browser cookies, or raw access tokens to Supabase.
