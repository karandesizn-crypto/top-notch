import Foundation
import CoreGraphics

/// Sizes for the notch surface in each state.
///
/// The panel is **exactly the camera housing's size** — 185 x 32pt on a 14-inch MacBook
/// Pro, measured from `auxiliaryTopLeftArea`, `auxiliaryTopRightArea` and
/// `safeAreaInsets.top` rather than hard-coded. Sitting directly beneath the housing at the
/// same width and height, it reads as the notch simply being twice as tall.
///
/// The chips sit together as one group, centred directly beneath the camera.
///
/// They cannot sit *on* the camera — it has no pixels behind it — and splitting them either
/// side of it breaks the group. So the drawn surface hangs just below the housing, narrower
/// than it, and merges with it because both are black.
///
/// Above the drawn surface the window still spans the camera's own row as an invisible
/// hover band. Nothing is drawn there, so nothing is covered, but hovering it is what tucks
/// the chips away — the gesture stays on the notch itself.
public struct NotchSurfaceLayout: Sendable, Equatable {
    /// Width of the physical camera housing; the surface is never narrower than this, or
    /// the notch would poke out either side of it.
    public let notchWidth: CGFloat
    /// Height of the invisible hover band over the camera's own row.
    ///
    /// Nothing is drawn here; it exists so hovering the notch can tuck the chips away.
    public let housingRowHeight: CGFloat

    /// Smallest a chip may become before the panel is allowed to outgrow the housing.
    public let minimumChipWidth: CGFloat
    /// Whether the add button is shown; hidden once the row is full.
    public let showsAddButton: Bool
    public let horizontalPadding: CGFloat
    /// Outward flare where the surface meets the top of the display.
    public let flare: CGFloat
    /// Height of the two-line snippet shown on hover.
    public let snippetHeight: CGFloat
    /// Height of one window row in the pinned breakdown: its label line plus its bar.
    public let pinnedRowHeight: CGFloat
    /// Height of the breakdown's own title line.
    public let pinnedTitleHeight: CGFloat
    /// The mini-notch: a small nub left behind when the chips are tucked away.
    public let miniNotchWidth: CGFloat
    public let miniNotchHeight: CGFloat
    public let bodyVerticalPadding: CGFloat
    public let providerCount: Int

    public init(
        providerCount: Int,
        notchWidth: CGFloat = 0,
        housingRowHeight: CGFloat = 32,
        showsAddButton: Bool = true,
        minimumChipWidth: CGFloat = 34,
        horizontalPadding: CGFloat = 8,
        flare: CGFloat = 12,
        snippetHeight: CGFloat = 34,
        pinnedRowHeight: CGFloat = 22,
        pinnedTitleHeight: CGFloat = 2,
        miniNotchWidth: CGFloat = 38,
        miniNotchHeight: CGFloat = 5,
        bodyVerticalPadding: CGFloat = 9
    ) {
        self.providerCount = max(providerCount, 1)
        self.notchWidth = notchWidth
        self.housingRowHeight = housingRowHeight
        self.showsAddButton = showsAddButton
        self.minimumChipWidth = minimumChipWidth
        self.horizontalPadding = horizontalPadding
        self.flare = flare
        self.snippetHeight = snippetHeight
        self.pinnedRowHeight = pinnedRowHeight
        self.pinnedTitleHeight = pinnedTitleHeight
        self.miniNotchWidth = miniNotchWidth
        self.miniNotchHeight = miniNotchHeight
        self.bodyVerticalPadding = bodyVerticalPadding
    }

    /// Items in the provider row: one per provider, plus the add button.
    public var itemCount: Int {
        providerCount + (showsAddButton ? 1 : 0)
    }

    /// A widening smaller than this is snapped away rather than drawn.
    ///
    /// The panel is allowed to grow past the housing when the chips would otherwise be
    /// squeezed, and that flare reads as deliberate once it is wide enough to see. Below
    /// that it does not: it overhangs the physical notch by a fraction of a point on each
    /// side, and the shoulder curve spreads that fraction over a ten-point drop, turning a
    /// single pixel of overflow into a small ear at the notch's lower corners — right where
    /// the eye is already comparing the surface against the hardware.
    ///
    /// Found with four providers: five items need 186pt against a 185pt notch, so the panel
    /// won by one point. Snapping costs each chip a fifth of a point.
    public static let flareSnapThreshold: CGFloat = 6

    /// The resting panel: the housing's own size, exactly.
    ///
    /// It only grows past the housing's width when the chips would otherwise be squeezed
    /// below `minimumChipWidth` — past a certain number of tools, legibility wins over the
    /// silhouette — and then only by an amount large enough to read as intended.
    public var collapsedSize: CGSize {
        let needed = CGFloat(itemCount) * minimumChipWidth + horizontalPadding * 2
        let overflow = needed - notchWidth
        let width = overflow > Self.flareSnapThreshold ? needed : notchWidth
        return CGSize(width: max(width, notchWidth), height: housingRowHeight)
    }

    public var collapsedHeight: CGFloat { collapsedSize.height }

    /// Width of one chip: the panel divides its width evenly between them.
    public var chipWidth: CGFloat {
        guard itemCount > 0 else { return minimumChipWidth }
        return (collapsedSize.width - horizontalPadding * 2) / CGFloat(itemCount)
    }

    /// Height of the chip row: the panel's full height.
    public var chipRowHeight: CGFloat { collapsedSize.height }

    /// Total width the chips occupy.
    public var contentWidth: CGFloat {
        collapsedSize.width - horizontalPadding * 2
    }

    /// Minimized: a mini-notch — a small nub below the camera.
    ///
    /// Not nothing. Drawing nothing leaves the way back invisible, and an affordance the
    /// user cannot see is one they cannot use. The nub is small enough to ignore while
    /// working and large enough to aim at.
    public var minimizedSize: CGSize {
        CGSize(width: miniNotchWidth, height: miniNotchHeight)
    }

    /// Vertical offset of the drawn surface inside the window: it hangs below the camera.
    public var surfaceTopInset: CGFloat { housingRowHeight }

    /// Height added on hover, and the extra line a click adds.
    ///
    /// Small either way: hovering shows the window that matters and when it resets, not a
    /// full panel. Clicking adds one line, because a deliberate click asks for a little
    /// more than a passing glance does.
    /// The most window rows the breakdown will ever draw.
    ///
    /// The window is sized once for the tallest reachable state, so a provider with four
    /// windows does not force a window resize mid-animation. Claude reports the most —
    /// session, weekly, and per-model weeklies — and four covers it.
    public static let maximumPinnedRows = 4

    public func expandedBodyHeight(pinned: Bool, rows: Int = 0) -> CGFloat {
        let breakdown = pinned
            ? pinnedTitleHeight + CGFloat(min(max(rows, 0), Self.maximumPinnedRows)) * pinnedRowHeight
            : 0
        return bodyVerticalPadding * 2 + snippetHeight + breakdown
    }

    /// Expanding grows the panel downward only.
    ///
    /// Its width stays the resting width — the housing's — because a panel wider than the
    /// housing has to flare outward from it, and that overhang is what makes the surface
    /// look stuck on rather than part of the notch.
    public func expandedSize(pinned: Bool, rows: Int = 0) -> CGSize {
        CGSize(
            width: collapsedSize.width,
            height: collapsedSize.height + expandedBodyHeight(pinned: pinned, rows: rows)
        )
    }

    public func size(expanded: Bool, minimized: Bool, pinned: Bool, rows: Int = 0) -> CGSize {
        if minimized { return minimizedSize }
        return expanded ? expandedSize(pinned: pinned, rows: rows) : collapsedSize
    }

    /// Window size: wide and tall enough for every reachable state, so expanding is purely
    /// a SwiftUI animation with no window resize.
    public var windowSize: CGSize {
        let widest = max(expandedSize(pinned: true, rows: Self.maximumPinnedRows).width,
                         collapsedSize.width)
        return CGSize(
            // At least the housing's width, so the hover band covers the whole camera.
            width: max(widest, notchWidth),
            height: surfaceTopInset
                + expandedSize(pinned: true, rows: Self.maximumPinnedRows).height
        )
    }
}
