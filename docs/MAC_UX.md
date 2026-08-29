# Mac UX

SideNotch is a **top-notch** surface: a compact tab hanging below the camera housing at the
top centre of the display.

Superseded twice. The first draft was a right-edge side rail. The second straddled the
housing across the menu bar row and was too large. The current design hangs *below* the
chrome, which is smaller, simpler, and never competes with menu bar items.

## Anchoring

Every dimension of the *anchor* comes from the display, measured at runtime through
`NotchPlacement`:

- **Housing width and position** from `NSScreen.auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea` — the housing is whatever those two areas do not cover. On the
  machine this was developed against that is 185pt, centred at x=756.
- **Housing height** from `NSScreen.safeAreaInsets.top` — 32pt, where the menu bar is 22pt.
- **Anchor** at the housing's *lower* edge, so the tab reads as the dark strip above
  continuing downward.

The tab's own size is a design token, not hardware-derived: it hangs below the housing
rather than fitting around it, so it does not need to know how wide the housing is.

### Displays without a housing

`safeAreaInsets.top` is zero, so the tab anchors to the bottom of the menu bar instead.
Same shape, same behaviour, nothing covered.

## States

### Collapsed

One chip per provider — a small ring and its figure — and nothing else.

```
     ╭─────────────────────────────╮
     │  ◔ 73%   ◔ 21%   ◔ 52%      │
     ╰─────────────────────────────╯
```

It answers one question: *is my usage okay?* The figure shown is the **most constrained**
window, because that is the limit that will bite first.

The tab is only as wide as its providers need — three chips is 228pt, four is 290pt.

### Expanded

The chip row does not move. It stays exactly where it is and doubles as the provider
switcher; the detail card is revealed beneath it. Nothing relayouts, which is what makes it
read as one surface changing shape rather than a panel appearing.

```
     ╭─────────────────────────────╮
     │  ◔ 73%   ◔ 21%   ◔ 52%      │
     │                             │
     │  ✳ Claude Usage       MAX   │
     │  5-hour      Resets in 51m  │
     │  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░         │
     │  73% used                   │
     │  Weekly     Resets Tue 7 PM │
     │  ▓▓▓▓░░░░░░░░░░░░░░         │
     │  21% used                   │
     ╰─────────────────────────────╯
```

Body height follows its content. A provider reporting one window does not reserve the room
a two-window provider needs.

## Providers

Three ship with adapters: **Claude, Codex, Cursor**. Only Codex reports live usage today;
the other two are documented unsupported adapters (see `docs/DATA_SOURCES.md`).

Users can add their own — Antigravity, an internal gateway, anything — in Settings. A
custom provider appears in the row and reports honestly that SideNotch has no interface it
can read. That is deliberate: someone working across four assistants wants all four in the
row, and inventing an integration would be worse than admitting there isn't one. When a
tool ships a supported local interface, writing an adapter is the only change needed.

`ProviderID` is a string wrapper rather than an enum precisely so this needs no code change
per tool. The row is capped at six, so the tab cannot outgrow the display.

## Silhouette

- Full width at the top, flaring inward through a **concave** curve. That hollow joins the
  tab to the chrome above rather than sticking it on.
- Generous bottom radii, larger when expanded.
- Near-black rather than pure black, so the tab separates from the housing by a hair in
  bright rooms while still reading as one object.
- The tab draws its own shadow; the window has none, since a window shadow would trace the
  full rectangle and give the game away.

## Interaction

| Action | Result |
|---|---|
| Pointer over the tab | Expands |
| Pointer leaves | Collapses, unless pinned |
| Click | Pins open, and takes key focus so the keyboard works |
| Escape | Collapses a pinned tab |
| Click a chip | Switches provider, and expands if collapsed |
| Menu bar item | Refresh, settings, quit |

Ambient by default: hovering never activates the app, so it cannot steal focus from the
editor. Only a deliberate click does.

Everything outside the drawn shape is click-through. The window is sized once for the
largest state, so expanding needs no window resize, and hit testing follows the drawn
silhouette rather than the window rectangle.

## Colour

One source: `UsageState`, derived from the user's thresholds by `UsageStateEvaluator`.
There is deliberately no second colour ramp — two systems would let the ring disagree with
the alerts. An earlier build had one; it was removed.

Because there is only one system, the *thresholds* carry the design intent. They default to
**50% warning / 70% critical**, which makes 21% read calm, 52% noticed, and 73% hot, as the
visual reference does. Both are adjustable in Settings, and alerts fire once per escalation
per window.

## Motion

One spring for the whole surface, so shape, width, height, and content move together. High
damping: a system surface transforming, not a widget bouncing. Reduce Motion replaces every
spring with a short ease and stops the loading ring spinning.
