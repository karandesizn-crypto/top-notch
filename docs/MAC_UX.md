# Mac UX

SideNotch is a **top-notch** surface. It occupies the row containing the camera housing at
the top centre of the display and reads as that housing continuing downward — not as a
window, popover, or menu.

Superseded: earlier drafts of this document described a right-edge side rail. That approach
was built and then replaced; the notch is now the anchor of the interaction.

## Anchoring

Every dimension comes from the display, measured at runtime through `NotchPlacement`:

- **Housing width and position** from `NSScreen.auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea` — the housing is whatever those two areas do not cover. On the
  machine this was developed against that is 185pt, centred at x=756.
- **Housing height** from `NSScreen.safeAreaInsets.top` — 32pt, which is taller than the
  22pt menu bar. Content must clear the housing, not just the menu bar.
- **Anchor** at the very top of the display, so the surface merges with the housing.

Nothing is hard-coded to a Mac model or resolution.

### Displays without a housing

`safeAreaInsets.top` is zero, so the surface anchors to the bottom of the menu bar and
hangs below it instead of covering menu items across the centre of the screen. The reserved
housing width becomes zero and the two content flanks meet in the middle, giving a
continuous strip.

## States

### Collapsed

A compact strip either side of the housing.

```
        ✳ Claude  │ housing │  ◯ 73%
```

It answers one question — *is my usage okay?* — and nothing else. Provider on the left,
ring and percentage on the right. The percentage shown is the **most constrained** window,
because that is the limit that will bite first.

### Expanded

The same surface grows downward. The housing row does not move: expanding reveals content
beneath it rather than relaying what was already there, which is what makes it read as one
object changing shape instead of a panel appearing.

```
        ✳ Claude  │ housing │  ◯ 73%
        ╭──────────────────────────────╮
        │  ◯     Current session  73%  │
        │  73%   ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░    │
        │        Resets in 51 min      │
        │                              │
        │   Claude  Codex  Cursor      │
        ╰──────────────────────────────╯
```

Body height follows its content. A provider reporting one window does not reserve the room
a two-window provider needs.

## Silhouette

- Full width at the very top, flaring inward through a **concave** curve. That hollow is
  what joins the surface to the bezel rather than sticking it on.
- Large bottom radii, so the shape stays continuous instead of reading as a rounded
  rectangle.
- Near-black rather than pure black, so the surface separates from the housing by a hair in
  bright rooms while still reading as one object.
- The surface draws its own shadow; the window has none, since a window shadow would trace
  the full rectangle and give the game away.

## Interaction

| Action | Result |
|---|---|
| Pointer over the surface | Expands |
| Pointer leaves | Collapses, unless pinned |
| Click | Pins open, and takes key focus so the keyboard works |
| Escape | Collapses a pinned surface |
| Click a provider | Switches, with the selection pill sliding rather than cross-fading |
| Menu bar item | Refresh, settings, quit |

The surface is ambient. It never activates the app on hover, so it cannot steal focus from
the editor the user is actually working in — only a deliberate click does that.

Everything outside the drawn shape is click-through. The window is always sized for the
largest state so expanding needs no window resize, and hit testing follows the drawn
silhouette rather than the window rectangle.

## Colour

One source: `UsageState`, derived from the user's configured thresholds by
`UsageStateEvaluator`. There is deliberately no second colour ramp — two systems would let
the ring disagree with the alerts.

An earlier build did have a separate continuous ramp for the ring. It was removed.

## Motion

One spring for the whole surface, so shape, width, height, and content move together. High
damping: the brief is a system surface transforming, not a widget bouncing. Reduce Motion
replaces every spring with a short ease and stops the loading ring spinning.
