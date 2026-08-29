Geometry for a surface attached to a Mac's camera housing.

Kept apart from `SideNotchCore` because it is presentation geometry, not domain: it knows
about displays, pixels and layout, and nothing about usage, providers or limits. Core knows
the opposite. Mixing them meant a change to how the notch is drawn touched the same module
as the meaning of a usage reading.

Pure value types and arithmetic — no AppKit, no SwiftUI — so the cases that are painful to
reproduce by hand (notched displays, external monitors at negative origins, screens shorter
than the surface) are unit tested rather than eyeballed.
