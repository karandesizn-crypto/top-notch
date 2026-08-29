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
  `auxiliaryTopRightArea` — the housing is whatever those two areas do not cover.
- **Housing height** from `NSScreen.safeAreaInsets.top`, which is taller than the menu bar.

Measured on a 14-inch MacBook Pro (1512x982pt, 3024x1964 native, @2x):

| | points | native pixels |
|---|---|---|
| Housing | **185.0 x 32.0** | 370 x 64 |
| Spans x | 663.5 … 848.5 | |
| Centre | 756.0 — exactly the screen's midpoint | |
| Menu bar | 22.0 tall | |

The auxiliary areas report their own height as 32.0, agreeing with the safe-area inset.
Aspect is 5.78 : 1. None of this is hard-coded: another Mac with a different housing gets a
panel matching *its* housing, and there is a test for that.
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

The panel is **exactly the housing's size** — 185 x 32pt — directly beneath it.

```
      ┌──────────────┐
      │    camera    │   185 x 32
      ├──────────────┤
      │  ◔  ◔  ◔  +  │   185 x 32
      ╰──────────────╯
```

Same width, same height, so the whole thing reads as a notch of double height rather than
as a panel attached to one. The chips sit **together**, not split either side of the camera:
they cannot sit *on* it, since there are no pixels behind the housing, so they go below.

The panel divides its width evenly between the chips. It only grows past the housing when
enough tools are added that the chips would fall below a legible width — past that point,
legibility wins over the silhouette, and only the width gives; the height stays matched.

### Hovering a chip

Hovering any ring sweeps **all** of them for one turn, and opens that provider's snippet.

The sweep on hover is animation only — it does not re-read anything. Hovering is passive and
constant, and refreshing on it would hammer the providers' local interfaces for no benefit.
A click is what actually re-reads. The ring draws both identically, so the feedback is
consistent either way.

Moving along the row does not restart the sweep; it stays one continuous turn rather than
stuttering chip to chip.


The panel grows **downward only**. Its width stays the housing's in every state: a panel
wider than the housing has to flare outward from it, and that overhang is what made the
surface look stuck on rather than part of the notch.

Fitting inside 185pt is what the snippet's phrasing is built around. Beyond a day out the
reset drops its time of day — "resets Sep 29, 1:38 AM" does not fit beside a percentage, and
the hour is not what someone glancing at a monthly window needs. Within a day the countdown
is the useful part, so it stays.


A two-line snippet drops below the group: which provider and window, then the figure and its
reset.

```
      ╭──────────────────────╮
      │  ◔  ◔  ◔  +          │
      │  ✳ Claude · 5-hour   │
      │  73% used · resets…  │
      ╰──────────────────────╯
```

A glance, not a panel. The most constrained window is the one shown, so a provider
reporting several does not make it taller; the limit that will bite first is the only one
worth reading here.

### Clicking a chip

A click selects the provider, pins the snippet open, and **re-reads every tool** — not just
the one clicked. Each ring shows a bright arc travelling around it while its read is in
flight, layered over the existing figure rather than replacing it, so the numbers stay
readable during the refresh instead of blinking away.

Each sweep is a **separate, smaller ring inside the usage track**, not layered over it —
overlaying the two meant the sweep obscured the very figure it was refreshing. It turns once
every 1.3s, both measured off the product's demo recording rather than guessed.

The reads are staggered by 90ms so the rings animate as a cascade rather than in unison,
which reads as the surface responding rather than as a glitch. A refresh holds its indicator
for one full turn — 1.3s — so the sweep completes a revolution and comes to rest where it
started, instead of stopping a third of the way round when a local read returns in
milliseconds. Only the indicator waits; the figures are published the moment they arrive.

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

One shape spans the camera housing and the panel beneath it.

The top section is the housing's own width and sits inside the notch row, where the display
has no pixels — invisible, but it is what makes the outline continuous. At the housing's
lower edge the outline necks in to the panel's width through a concave curve that mirrors
the hardware's own shoulders, so the panel reads as the notch continuing downward.

Three things had made it read as a separate pill stuck underneath:

- **Its own rounded top corners**, meeting the housing's rounded bottom corners, which never
  lined up. There is now a single outline with no join.
- **A lighter fill.** The surface was near-black, chosen so it would separate from the
  housing by a hair. On real hardware that hair is a visible seam: the housing is true
  black, and anything lighter beside it looks like a different object. The fill is now pure
  black.
- **A hairline border**, which traced the panel's edge against the housing. Removed.

The panel's bottom corners keep a generous radius, larger when expanded. The minimized
mini-notch uses the same outline with a tiny body, so even tucked away it is part of the
notch rather than a nub floating below it.

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
