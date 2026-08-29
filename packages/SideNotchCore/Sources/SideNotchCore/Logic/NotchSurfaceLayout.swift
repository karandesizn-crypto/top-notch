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
    /// Width of one provider chip.
    public let chipWidth: CGFloat
    /// Width of the trailing add button.
    public let addChipWidth: CGFloat
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
        chipRowHeight: CGFloat = 62,
        chipWidth: CGFloat = 64,
        addChipWidth: CGFloat = 40,
        horizontalPadding: CGFloat = 12,
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
        self.chipWidth = chipWidth
        self.addChipWidth = addChipWidth
        self.horizontalPadding = horizontalPadding
        self.flare = flare
        self.expandedWidth = expandedWidth
        self.contentRowHeight = contentRowHeight
        self.contentRowSpacing = contentRowSpacing
        self.cardTitleHeight = cardTitleHeight
        self.bodyVerticalPadding = bodyVerticalPadding
    }

    /// Widths of the items in the provider row, in order.
    public var itemWidths: [CGFloat] {
        Array(repeating: chipWidth, count: providerCount)
            + (showsAddButton ? [addChipWidth] : [])
    }

    public var contentWidth: CGFloat {
        itemWidths.reduce(0, +) + horizontalPadding * 2
    }

    /// The collapsed surface: the housing band plus one continuous provider row.
    ///
    /// Never narrower than the housing plus its flares, so the notch cannot show past the
    /// surface's edges.
    public var collapsedSize: CGSize {
        CGSize(
            width: max(contentWidth + flare * 2, notchWidth + flare * 2),
            height: housingRowHeight + chipRowHeight
        )
    }

    public var collapsedHeight: CGFloat { collapsedSize.height }

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

    public func size(expanded: Bool, rowCount: Int) -> CGSize {
        expanded ? expandedSize(rowCount: rowCount) : collapsedSize
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
