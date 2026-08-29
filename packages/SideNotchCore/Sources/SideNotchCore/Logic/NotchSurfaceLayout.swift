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
    public let contentRowHeight: CGFloat
    public let contentRowSpacing: CGFloat
    public let cardTitleHeight: CGFloat
    public let bodyVerticalPadding: CGFloat
    public let providerCount: Int

    /// Window rows reserved for the busiest provider, so switching never resizes the window.
    public static let maximumRows = 2

    public init(
        providerCount: Int,
        notchWidth: CGFloat = 0,
        housingRowHeight: CGFloat = 32,
        showsAddButton: Bool = true,
        chipRowHeight: CGFloat = 46,
        minimumChipWidth: CGFloat = 34,
        horizontalPadding: CGFloat = 8,
        flare: CGFloat = 12,
        expandedWidth: CGFloat = 322,
        contentRowHeight: CGFloat = 42,
        contentRowSpacing: CGFloat = 9,
        cardTitleHeight: CGFloat = 20,
        bodyVerticalPadding: CGFloat = 11
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
        self.contentRowHeight = contentRowHeight
        self.contentRowSpacing = contentRowSpacing
        self.cardTitleHeight = cardTitleHeight
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

    /// Height of the expanded body, following the content it actually holds.
    ///
    /// A provider reporting one window must not reserve the room a two-window provider
    /// needs, or the surface opens onto empty space.
    public func expandedBodyHeight(rowCount: Int) -> CGFloat {
        let rows = max(rowCount, 1)
        let rowsHeight = CGFloat(rows) * contentRowHeight
            + CGFloat(rows - 1) * contentRowSpacing
        // The trailing spacing is the gap between the card title and the first row.
        return bodyVerticalPadding * 2 + cardTitleHeight + contentRowSpacing + rowsHeight
    }

    public func expandedSize(rowCount: Int) -> CGSize {
        CGSize(
            width: max(expandedWidth, collapsedSize.width),
            height: collapsedSize.height + expandedBodyHeight(rowCount: rowCount)
        )
    }

    /// The largest the surface can get, which is what the window is sized for.
    public var maximumExpandedSize: CGSize {
        expandedSize(rowCount: Self.maximumRows)
    }

    public func size(expanded: Bool, minimized: Bool, rowCount: Int) -> CGSize {
        if minimized { return minimizedSize }
        return expanded ? expandedSize(rowCount: rowCount) : collapsedSize
    }

    /// Window size: wide and tall enough for every reachable state, so expanding is purely
    /// a SwiftUI animation with no window resize.
    public var windowSize: CGSize {
        CGSize(
            width: max(maximumExpandedSize.width, collapsedSize.width),
            height: maximumExpandedSize.height
        )
    }
}
