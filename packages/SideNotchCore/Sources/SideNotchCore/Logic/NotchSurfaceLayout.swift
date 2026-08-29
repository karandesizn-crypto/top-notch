import Foundation
import CoreGraphics

/// Sizes for the notch surface in each state.
///
/// The surface starts in the notch row and extends below it. The top band is the height of
/// the camera housing and stays empty — nothing can render over the camera — so it reads as
/// the notch itself. All content sits beneath that band, where the display is unobstructed,
/// which is what lets the provider row run continuously instead of splitting around the
/// housing.
public struct NotchSurfaceLayout: Sendable, Equatable {
    /// Width of the physical camera housing; the surface is never narrower than this, or
    /// the notch would poke out either side of it.
    public let notchWidth: CGFloat
    /// Height of the empty band that merges with the housing.
    public let housingRowHeight: CGFloat
    /// Height of the provider row: ring plus its figure.
    public let chipRowHeight: CGFloat
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
        chipRowHeight: CGFloat = 46,
        minimumChipWidth: CGFloat = 34,
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
        self.chipRowHeight = chipRowHeight
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

    /// Width available to the row inside the surface.
    public var contentWidth: CGFloat {
        max(collapsedSize.width - flare * 2 - horizontalPadding * 2, 0)
    }

    /// Width of one chip: the row divides the available width evenly.
    public var chipWidth: CGFloat {
        guard itemCount > 0 else { return minimumChipWidth }
        return contentWidth / CGFloat(itemCount)
    }

    /// The collapsed surface is **exactly the width of the camera housing**, so it reads as
    /// the notch itself rather than a bar poking out either side of it.
    ///
    /// It only grows past the housing when the chips would otherwise be squeezed below
    /// `minimumChipWidth` — with enough tools added, legibility wins over the silhouette.
    public var collapsedSize: CGSize {
        let needed = CGFloat(itemCount) * minimumChipWidth
            + horizontalPadding * 2 + flare * 2
        return CGSize(
            width: max(notchWidth, needed),
            height: housingRowHeight + chipRowHeight
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
