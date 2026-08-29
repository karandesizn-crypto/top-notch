import Foundation
import CoreGraphics

/// Sizes for the notch surface in each state.
///
/// At rest the surface is **only the notch row**: the height of the camera housing, with
/// the chips sitting either side of the camera. Nothing extends below the menu bar, so
/// nothing on the desktop is ever covered or made unclickable.
///
/// The camera has no pixels behind it, so content cannot be centred on the notch — it has
/// to go beside it. That is why the resting strip is wider than the housing even though it
/// is exactly as tall.
///
/// Hovering a chip drops a snippet below the row; hovering the housing band tucks even the
/// chips away.
public struct NotchSurfaceLayout: Sendable, Equatable {
    /// Width of the physical camera housing; the surface is never narrower than this, or
    /// the notch would poke out either side of it.
    public let notchWidth: CGFloat
    /// Height of the empty band that merges with the housing.
    public let housingRowHeight: CGFloat
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
    public let bodyVerticalPadding: CGFloat
    public let providerCount: Int

    public init(
        providerCount: Int,
        notchWidth: CGFloat = 0,
        housingRowHeight: CGFloat = 32,
        showsAddButton: Bool = true,
        chipWidth: CGFloat = 28,
        minimumChipWidth: CGFloat = 24,
        horizontalPadding: CGFloat = 8,
        flare: CGFloat = 12,
        expandedWidth: CGFloat = 232,
        snippetHeight: CGFloat = 34,
        bodyVerticalPadding: CGFloat = 9
    ) {
        self.providerCount = max(providerCount, 1)
        self.notchWidth = notchWidth
        self.housingRowHeight = housingRowHeight
        self.showsAddButton = showsAddButton
        self.chipWidth = max(chipWidth, minimumChipWidth)
        self.minimumChipWidth = minimumChipWidth
        self.horizontalPadding = horizontalPadding
        self.flare = flare
        self.expandedWidth = expandedWidth
        self.snippetHeight = snippetHeight
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

    /// How many chips sit to the left of the camera.
    ///
    /// Split as evenly as possible with the remainder on the left, so an odd number still
    /// looks deliberate rather than lopsided.
    public var leadingItemCount: Int {
        (itemCount + 1) / 2
    }

    public var leadingFlankWidth: CGFloat {
        CGFloat(leadingItemCount) * chipWidth
    }

    public var trailingFlankWidth: CGFloat {
        CGFloat(itemCount - leadingItemCount) * chipWidth
    }

    /// The resting strip: exactly the housing's height, with the chips either side of it.
    ///
    /// It is wider than the housing by necessity — the camera has no pixels behind it — but
    /// it is no taller, so it lives entirely within the menu bar row and covers nothing.
    public var collapsedSize: CGSize {
        CGSize(
            width: notchWidth + contentWidth + horizontalPadding * 2 + flare * 2,
            height: housingRowHeight
        )
    }

    public var collapsedHeight: CGFloat { collapsedSize.height }

    /// Minimized: only the band that merges with the housing.
    ///
    /// The housing row has no pixels on a notched display, so a surface this size covers
    /// nothing and every window beneath it stays clickable.
    public var minimizedSize: CGSize {
        CGSize(width: max(notchWidth, minimumChipWidth * 2), height: housingRowHeight)
    }

    /// Whether a chip belongs on the left of the camera.
    public func isLeading(itemIndex: Int) -> Bool {
        itemIndex < leadingItemCount
    }

    /// Height added on hover.
    ///
    /// Fixed, and small: hovering shows a snippet — the window that matters and when it
    /// resets — not a full panel. A provider with two windows gets the more constrained
    /// one rather than a taller card.
    public var expandedBodyHeight: CGFloat {
        bodyVerticalPadding * 2 + snippetHeight
    }

    public var expandedSize: CGSize {
        CGSize(
            width: max(expandedWidth, collapsedSize.width),
            height: collapsedSize.height + expandedBodyHeight
        )
    }

    public func size(expanded: Bool, minimized: Bool) -> CGSize {
        if minimized { return minimizedSize }
        return expanded ? expandedSize : collapsedSize
    }

    /// Window size: wide and tall enough for every reachable state, so expanding is purely
    /// a SwiftUI animation with no window resize.
    public var windowSize: CGSize {
        CGSize(
            width: max(expandedSize.width, collapsedSize.width),
            height: expandedSize.height
        )
    }
}
