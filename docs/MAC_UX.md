# Mac UX Scaffold

## State 0 — dormant
Right-edge side rail is minimized and visually quiet.

## State 1 — rail
Vertical provider stack:
- provider mark
- circular usage ring
- percentage

## State 2 — focused provider
Click/hover on provider expands a card to the left.

Card hierarchy:
1. Provider name + mark
2. Usage scope
3. progress bar
4. percentage used
5. reset countdown
6. secondary usage scope when available
7. last updated / stale status

## State 3 — warning
When a provider reaches threshold:
- ring changes semantic state
- subtle pulse once, not continuously
- optional notification

## State 4 — exhausted
Show explicit exhausted state and next reset time.

## Interaction principles
- No dashboard required for the primary task.
- One glance should answer: “Am I close to a limit?”
- One interaction should answer: “Which limit, and when does it reset?”
- Avoid persistent large windows.
- Respect Reduce Motion and Increase Contrast.
