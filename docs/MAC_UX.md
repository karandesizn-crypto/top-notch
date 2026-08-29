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
- **Anchor** at the very top of the display, so the collapsed surface *occupies the notch
  row* rather than hanging below it. Its height matches the housing exactly and its chips
  sit either side of the camera, which is what makes it read as part of the notch.

The housing's width is a hole in the layout, not a spacer with something behind it: nothing
can render over the camera, so the row reserves its measured width and splits the chips
around it — the extra one going left when the count is odd.

### Which display, and when nothing shows

A notched display always wins, even when an external monitor has focus. Two reasons: the
surface has nothing to attach to on a display without a housing — it just floats over
whatever window is at the top edge — and pinning it to the built-in screen means it stays
put while the user works on the external one.

**With no notched display attached, nothing is shown at all.** The menu bar item remains
the way in. "Show on displays without a notch" in Settings opts back in, for Macs that have
no notch at all; there the surface anchors below the menu bar rather than over it, since a
non-notched Mac has no dead zone in the middle to borrow, and the reserved housing width
becomes zero so the two flanks meet.

The rule lives in `NotchPlacement.preferredDisplayIndex`, away from AppKit, so the cases
that need hardware to reproduce are unit tested instead.

### What this costs

Sitting in the notch row means the surface is drawn over the menu bar either side of the
camera. That area is normally empty — menus end well to the left and status items begin
well to the right — but an app with many menus, or many status items, can reach under it.
Clicks pass through everywhere the surface is *not* drawn, so only the strip it actually
covers is affected.

## States

### Resting

One group of chips, centred directly beneath the camera.

```
        ┌──────────┐
        │  camera  │
      ╭─┴──────────┴─╮
      │  ◔  ◔  ◔  +  │   <- 148 x 34pt, narrower than the housing
      ╰──────────────╯
```

The chips sit **together**, not split either side of the camera. They cannot sit *on* it —
there are no pixels behind the housing — so the group hangs just below, narrower than the
housing, and merges with it because both are black. That reads as the notch continuing
downward rather than as a bar of its own.

The group is sized to its chips, so it never reserves width for the camera. Adding a tool
widens it by one chip.

### Hovering a chip

A two-line snippet drops below the group: which provider and window, then the figure and its
reset.

```
      ╭──────────────────────╮
      │  ◔  ◔  ◔  +          │
      │  ✳ Claude · 5-hour   │
      │  73% used · resets…  │
      ╰──────────────────────╯
```

A glance, not a panel — 232×86. The most constrained window is the one shown, so a provider
reporting several does not make it taller; the limit that will bite first is the only one
worth reading here.

### Clicking a chip

A click selects the provider, pins the snippet open, and **re-reads that provider**. The
ring shows a bright arc travelling around it while the read is in flight, layered over the
existing figure rather than replacing it, so the number stays readable during the refresh
instead of blinking away.

Re-reading on click is the point: a deliberate click usually means *is this still true?*,
and the sweep answers that the question was heard even when the figure comes back unchanged.

A pinned snippet earns one more line than a hovered one — plan, the other window, reset
credits, tokens today — built only from what the provider actually reported, so it is short
or absent entirely for a sparse provider.

### The mini-notch

Above the group, the window spans the camera's own row as an **invisible hover band**.
Nothing is drawn there, so nothing is covered, but hovering it tucks the chips away.

What is left is a **mini-notch**: a 38×5pt nub just below the camera. Not nothing — drawing
nothing would leave the way back invisible, and an affordance nobody can see is one nobody
can use. It is small enough to ignore while working and has a forgiving hit area for its
size. Hovering it brings the group straight back.

Keeping the hide gesture on the camera itself is deliberate: it is the one part of the menu
bar row that never holds anything else. It toggles on entry rather than continuously, so one
pass of the pointer fires it once instead of flickering while the pointer rests there.

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
