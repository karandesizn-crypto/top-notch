# Running Top Notch on your own Mac

This is the personal-alpha setup: one machine, no Developer ID, no notarization, no
distribution. `docs/RELEASE.md` covers the public path and is parked until it is wanted.

## Install

```
./scripts/dev-install.sh
```

Builds release for arm64, installs to `~/Applications/Top Notch.app`, quits the running
copy, and launches the new one. Takes a few seconds after the first build.

```
./scripts/dev-install.sh --debug       # keeps the diagnostic env-var modes
./scripts/dev-install.sh --no-launch   # install without starting it
```

**Why `~/Applications` and not the repo.** The app has to keep running while the working
tree is rebuilt, moved, or cleaned. A bundle living inside the checkout does not survive
that — and did not: an earlier build was found still running hours after its folder had
been renamed, holding a Codex child process, invisible because the app has no Dock icon.
`~/Applications` also needs no `sudo`.

## Running it

No Dock icon and no window — that is `LSUIElement`, and it is intentional. The app is the
notch surface plus a menu bar item (gauge icon) with Refresh Now, Settings and Quit.

**Launch at login** is a toggle in Settings. It uses `SMAppService`, which needs a real
bundle — so it works from `~/Applications/Top Notch.app` and does nothing from a bare
`swift run`. It is off by default; turn it on once and the app is there every morning.

**Only one instance can run.** A second launch terminates the older one rather than
refusing to start, because after a rebuild what you want is the new build. This matters
more than it sounds: two instances each hold a Codex child process and each poll
independently, and since the rate limiter is per-process, two copies double the request
rate against an endpoint that rate-limits hard and stays limited for hours.

## The keychain prompt

The first time a given build reads Claude, macOS asks:

> "Top Notch wants to access key 'Claude Code-credentials' in your keychain."

Allow it. The app is reading Claude Code's own login rather than asking you for a new
credential — that is the whole design, and it never stores or refreshes what it reads.

**It comes back after a rebuild that changed the code, and that is not a bug.** An ad-hoc
signature has no stable identity, so the keychain binds the grant to the code hash. Change
the binary, and as far as the keychain is concerned it is a different program.
`dev-install.sh` tells you which case you are in:

```
keychain  signature changed — macOS will ask once for 'Claude Code-credentials'
keychain  unchanged signature — no new prompt expected
```

A rebuild with no source change keeps the same hash and does not prompt.

If you deny it by accident: Keychain Access → search `Claude Code-credentials` → Get Info →
Access Control, and remove Top Notch from the denied list. Codex and Cursor are unaffected
either way — neither touches the keychain.

**A stable signing identity would remove the prompt entirely**, by binding the grant to a
certificate rather than a hash. That means creating a self-signed code-signing certificate
in your login keychain — a persistent change to your system that is yours to make, not
mine. It is a reasonable thing to want if the rebuild prompt becomes tiresome; it is not
needed for the app to work.

## Checking on it

```
swift run --package-path tools/usage-probe usage-probe
```

Prints each provider's live state and, when there are no figures, the reason.

```
SIDENOTCH_PROBE_CREDS=1 swift run --package-path tools/usage-probe usage-probe
```

Credential health — which store answered, scopes, expiry — with **no network request**,
which matters because Anthropic's usage endpoint rate-limits hard and asking it again to
find out why it is refusing only extends the limit.

Logs:

```
log show --predicate 'subsystem == "com.hivinz.topnotch"' --last 10m --style compact
```

Nothing in there is a secret by construction: the logging rule is shapes and counts, never
payloads.

## What to expect day to day

- **Refresh**: every 5 minutes by default, adjustable in Settings. Also on wake, on manual
  refresh, and when Codex pushes a rate-limit update.
- **After sleep**: refreshes immediately on wake. The scheduler also checks the wall clock
  rather than trusting elapsed sleep, so a closed lid cannot leave stale figures on screen.
- **After a restart**: the cache restores the last reading marked `cached`, then the launch
  refresh replaces it with live figures a second later. Readings older than 24 hours are
  discarded rather than restored.
- **When a provider is unavailable**: the ring shows the unavailable treatment and the card
  says why. It never shows a stale number as if it were current, and never invents one.
- **Claude's token**: if it lapses, Claude reports "Sign-in expired" until Claude Code
  writes a fresh one. `claude auth login`, or any `claude -p` call, restores it. Top Notch
  will not renew a credential it did not issue — that is what protects your CLI session.

## Uninstalling

```
osascript -e 'quit app id "com.hivinz.topnotch"'
rm -rf ~/Applications/"Top Notch.app"
rm -rf ~/Library/Application\ Support/"Top Notch"
defaults delete com.hivinz.topnotch
```

Turn off Launch at Login in Settings first, or unregister it with
`SMAppService.mainApp.unregister()`. Nothing else is written anywhere.
