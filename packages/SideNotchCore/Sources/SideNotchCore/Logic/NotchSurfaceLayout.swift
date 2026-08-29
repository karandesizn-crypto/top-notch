import Foundation
import CoreGraphics

/// Sizes for the notch surface in each state.
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
    /// Height of the drawn chip row.
    public let chipRowHeight: CGFloat
    /// Width of one chip in the resting strip.
    public let chipWidth: CGFloat
    /// Smallest a chip may become before the row is allowed to outgrow the housing.
    public let minimumChipWidth: CGFloat
    /// Whether the add button is shown; hidden once the row is full.
    public let showsAddButton: Bool
    public let horizontalPadding: CGFloat
    /// Outward flare where the surface meets the top of the display.
    public let flare: CGFloat
    public let expandedWidth: CGFloat
    /// Height of the two-line snippet shown on hover.
    public let snippetHeight: CGFloat
    /// Extra height for the third line a click adds.
    public let pinnedExtraHeight: CGFloat
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
        chipRowHeight: CGFloat = 34,
        chipWidth: CGFloat = 28,
        minimumChipWidth: CGFloat = 24,
        horizontalPadding: CGFloat = 8,
        flare: CGFloat = 12,
        expandedWidth: CGFloat = 232,
        snippetHeight: CGFloat = 34,
        pinnedExtraHeight: CGFloat = 15,
        miniNotchWidth: CGFloat = 38,
        miniNotchHeight: CGFloat = 5,
        bodyVerticalPadding: CGFloat = 9
    ) {
        self.providerCount = max(providerCount, 1)
        self.notchWidth = notchWidth
        self.housingRowHeight = housingRowHeight
        self.showsAddButton = showsAddButton
        self.chipRowHeight = chipRowHeight
        self.chipWidth = max(chipWidth, minimumChipWidth)
        self.minimumChipWidth = minimumChipWidth
        self.horizontalPadding = horizontalPadding
        self.flare = flare
        self.expandedWidth = expandedWidth
        self.snippetHeight = snippetHeight
        self.pinnedExtraHeight = pinnedExtraHeight
        self.miniNotchWidth = miniNotchWidth
        self.miniNotchHeight = miniNotchHeight
        self.bodyVerticalPadding = bodyVerticalPadding
    }

    /// Items in the provider row: one per provider, plus the add button.
    public var itemCount: Int {
        providerCount + (showsAddButton ? 1 : 0)
    }

    /// Total width the chips occupy.
    public var contentWidth: CGFloat {
        CGFloat(itemCount) * chipWidth
    }

    /// The resting surface: one group of chips, sized to them alone.
    ///
    /// Narrower than the housing, which is what lets it read as the notch continuing
    /// downward rather than as a bar of its own.
    public var collapsedSize: CGSize {
        CGSize(
            width: contentWidth + horizontalPadding * 2 + flare * 2,
            height: chipRowHeight
        )
    }

    public var collapsedHeight: CGFloat { collapsedSize.height }

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
    public func expandedBodyHeight(pinned: Bool) -> CGFloat {
        bodyVerticalPadding * 2 + snippetHeight + (pinned ? pinnedExtraHeight : 0)
    }

    public func expandedSize(pinned: Bool) -> CGSize {
        CGSize(
            width: max(expandedWidth, collapsedSize.width),
            height: collapsedSize.height + expandedBodyHeight(pinned: pinned)
        )
    }

    public func size(expanded: Bool, minimized: Bool, pinned: Bool) -> CGSize {
        if minimized { return minimizedSize }
        return expanded ? expandedSize(pinned: pinned) : collapsedSize
    }

    /// Window size: wide and tall enough for every reachable state, so expanding is purely
    /// a SwiftUI animation with no window resize.
    public var windowSize: CGSize {
        let widest = max(expandedSize(pinned: true).width, collapsedSize.width)
        return CGSize(
            // At least the housing's width, so the hover band covers the whole camera.
            width: max(widest, notchWidth),
            height: surfaceTopInset + expandedSize(pinned: true).height
        )
    }
}
