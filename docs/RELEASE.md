# Releasing Top Notch

How this app is built, signed, notarized and distributed, and why each decision went the
way it did.

---

## The decision that shapes everything else: no App Sandbox

Top Notch cannot be sandboxed, and that is not a corner cut. All three integrations read
state that belongs to another application:

| Provider | Needs |
|---|---|
| Codex | Spawns `/Applications/Codex.app/Contents/Resources/codex` as a child process |
| Claude | Reads the `Claude Code-credentials` keychain item, and `~/.claude/.credentials.json` |
| Cursor | Reads `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` |

Every one of those is outside a sandbox container, and none has an entitlement that would
grant it. A sandboxed build would report all three providers unavailable — which is to say,
it would not be this product.

**Consequences, accepted deliberately:**

- **No Mac App Store.** The store requires sandboxing. Distribution is Developer ID plus
  notarization, direct download.
- **Gatekeeper matters more, not less.** Without the store's review as a trust signal,
  notarization is the only thing standing between a user and a scary dialog.
- **Least privilege has to come from design rather than from the sandbox.** The app holds
  no credential, writes nothing outside its own support directory, and makes exactly two
  kinds of network request. `docs/PROVIDER_INTEGRATIONS.md` records the specifics.

## Identity

| | |
|---|---|
| Bundle identifier | `com.hivinz.topnotch` |
| Display name | Top Notch |
| Category | `public.app-category.developer-tools` |
| Minimum macOS | 14.0 |
| `LSUIElement` | `true` — menu bar and notch only, no Dock icon |

**The bundle identifier is the one thing that must be settled before the first public
build.** macOS keys preferences, the login-item registration and the keychain ACL to it,
and Sparkle keys update eligibility to it. Changing it after release orphans every
installed copy: their settings vanish, their login item stops working, and they stop
receiving updates with no error to explain why. If `com.hivinz.topnotch` is not the final
identifier, change it in `scripts/release.sh` **now**, and change `Log.subsystem` in
`ProviderKit/Support/Log.swift` to match so Console filtering keeps working.

### Versioning

`CFBundleShortVersionString` is the marketing version (`1.0.0`). `CFBundleVersion` is a
UTC timestamp (`202608301106`), generated per build. Two separate fields because macOS and
Sparkle both compare the *build* number to decide what is newer, and a marketing string
like `1.0.0` cannot distinguish two builds of the same release. The timestamp is monotonic
without a counter that has to be kept in sync across machines.

The source revision is recorded in the bundle as `TopNotchSourceRevision`, so a bug report
identifies a build.

## Signing

```
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
```

- **Developer ID Application** certificate. Not Mac App Distribution — that is for the
  store this app cannot use.
- **`--options runtime`** enables the hardened runtime. Notarization rejects anything
  without it, so `validate-release.sh` checks for the `runtime` flag before submission
  rather than letting Apple deliver that news several minutes later.
- **`--timestamp`** attaches a secure timestamp, so the signature stays valid after the
  certificate expires.
- **No entitlements file, on purpose.** The hardened runtime restricts library injection,
  unsigned executable memory and DYLD overrides — none of which this app needs to relax.
  It does not restrict network access, spawning a child process, or reading files, which
  are the three things the app actually does. The least-privilege position is to request
  nothing, and that is what an auditor should find.

## Notarization

```
xcrun notarytool store-credentials "topnotch" \
    --apple-id you@example.com --team-id TEAMID --password <app-specific-password>

./scripts/release.sh --sign --notarize
```

`notarytool`, not `altool` — the latter was decommissioned. The **DMG** is submitted rather
than a zip, so the ticket can be stapled to the artefact the user actually downloads;
stapling a zip means unpacking it and stapling the app inside, which then has to be
re-packed.

`xcrun stapler staple` then `stapler validate`. Stapling is what lets the app pass
Gatekeeper on a machine that is offline or behind a filter — without it, first launch
depends on a successful round trip to Apple.

Submissions have been observed sitting "In Progress" for hours during Apple-side
incidents. Budget for it; do not schedule a launch that assumes minutes.

## Packaging

A UDZO-compressed DMG containing the app and an `/Applications` symlink, which is what
makes the drag-to-install gesture legible without a custom background image.

Universal (arm64 + x86_64). There is no App Store thinning on a direct download, so one
artefact has to serve both architectures; `validate-release.sh` fails the build if either
slice is missing.

## Update strategy

**Recommended: Sparkle 2 with EdDSA-signed appcasts.** It is the standard for
non-sandboxed direct-download Mac apps, and it fits this app's shape — `LSUIElement`,
Developer ID, DMG.

**It is deliberately not wired up yet**, because Sparkle needs an appcast hosted at a
stable URL, and pointing a shipped auto-updater at a server that does not exist is worse
than shipping without one: it fails quietly, on the users' machines, forever.

What is already in place for it:

- A stable bundle identifier.
- A monotonic `CFBundleVersion` — the field Sparkle actually compares.
- Notarized DMGs, which is the artefact format Sparkle expects.

To enable it, in order: generate an EdDSA key pair with Sparkle's `generate_keys`, publish
the public key in `Info.plist` as `SUPublicEDKey`, host `appcast.xml`, add
`SUFeedURL`, then add the Sparkle package dependency and a "Check for Updates…" menu item.
Until then the update path is manual: a new DMG, and a release note.

## First launch

What a new user actually experiences, in order. None of this is guesswork — it was
observed by installing the release build on this machine.

1. **Gatekeeper.** Signed and notarized: the app opens normally. Unsigned or ad-hoc: macOS
   refuses it outright and the user has to right-click → Open, which is exactly the
   friction notarization exists to remove.
2. **No Dock icon, no window.** `LSUIElement` means the only visible entry points are the
   notch surface and the menu bar item. This is intended, and it is worth saying plainly in
   the download page copy, because an app that "does nothing" on launch reads as broken.
3. **A keychain prompt, the first time Claude is read.** macOS asks:
   *"Top Notch wants to access key 'Claude Code-credentials' in your keychain."*

   This is the single most important thing to explain before a user meets it. It is
   correct, expected macOS behaviour — the app is reading Claude Code's own login rather
   than asking for a new one — but an unexplained keychain prompt from a usage monitor
   looks alarming, and a user who clicks Deny gets a permanently unavailable Claude with no
   obvious way back.

   Notes:
   - The prompt is tied to the **code signature**, so it appears again after any change of
     signing identity. It should appear exactly once for a given released build.
   - Denying it is recoverable: the entry can be corrected in Keychain Access, under the
     `Claude Code-credentials` item's Access Control tab.
   - Codex and Cursor are unaffected — they need no keychain access, and were verified
     returning live figures while the Claude prompt was still pending.

4. **A notification permission prompt.** For threshold alerts. Deliberately *not* on the
   path to reading usage — see below.
5. **Launch at login** is off by default and is opt-in from Settings. It uses
   `SMAppService`, which requires a signed bundle; it silently does nothing from a bare
   `swift run`.

### A bug this found

The startup sequence originally awaited the notification permission *before* starting the
usage manager. Ignoring that dialog therefore left the rail permanently empty, with the app
running and apparently healthy. Reading usage must never wait on permission to notify about
usage; the two now start as independent tasks. Caught only by installing the release build
and watching it do nothing.

## Release validation

`scripts/validate-release.sh` runs automatically at the end of `release.sh` and checks the
things that actually go wrong:

| Check | The failure it prevents |
|---|---|
| `CFBundleExecutable` matches the binary | A bundle that cannot launch at all |
| Universal binary | Silent exclusion of every Intel Mac |
| `minos` matches `LSMinimumSystemVersion` | A crash on launch for users on older macOS |
| `LSUIElement` set | An unwanted Dock icon in a menu-bar utility |
| Developer ID authority, not ad-hoc | Shipping a build Gatekeeper refuses |
| Hardened runtime flag | A notarization rejection several minutes in |
| Stapled ticket | Offline first launches being blocked |
| No `SIDENOTCH_RENDER` / `SIDENOTCH_MOCK` strings | A debug build shipped as release |
| No credential-shaped strings | The one mistake with no recovery |

The debug-surface checks read the shipped binary with `strings` rather than trusting the
`#if DEBUG` guards, because a guard is easy to get wrong and impossible to see.

---

## Shipping checklist

**Blocking — cannot ship without these**

- [ ] Enrol in the Apple Developer Program and install a **Developer ID Application**
      certificate. `security find-identity -v -p codesigning` currently reports
      `0 valid identities found` on this machine, so nothing distributable can be produced
      here yet.
- [ ] Confirm `com.hivinz.topnotch` is the final bundle identifier — it cannot change after
      the first release without orphaning every install.
- [ ] Create the notarytool keychain profile.
- [ ] `./scripts/release.sh --sign --notarize` and confirm every validation check passes.
- [ ] Install the DMG on a **second Mac** that has never built this app. This is the only
      way to test Gatekeeper and the first-launch experience honestly.
- [ ] Resolve the trademark question in `docs/PROVIDER_MARKS.md` — the app draws
      approximations of marks owned by Anthropic, OpenAI and Anysphere, and shipping them
      publicly needs a decision.

**Should do before a public launch**

- [ ] An app icon. There is currently no `.icns`, so macOS shows the generic placeholder.
- [ ] Download-page copy covering the keychain prompt and the no-Dock-icon behaviour.
- [ ] A privacy statement. It is short and unusually strong: no telemetry, no analytics, no
      account, no data leaves the machine except two authenticated requests to the user's
      own providers.
- [ ] Decide on Sparkle, and if yes, host the appcast before the first release rather than
      after.

**Known limitations to state publicly**

- [ ] Two of three integrations are undocumented vendor endpoints and may break without
      notice. They fail closed — the app reports unavailable, never a wrong number.
- [ ] Codex's `app-server` is marked `[experimental]` on an alpha CLI.
- [ ] A lapsed Claude Code token needs `claude auth login`; the app cannot and will not
      renew a credential it did not issue.
