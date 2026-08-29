import Foundation
import CoreGraphics

/// Sizes for the notch surface in each state.
///
/// The surface is a compact tab hanging below the camera housing, centred on it. It does
/// not straddle the housing, so there is no reserved hole and no flanks — content simply
/// lays out across the tab. That is both simpler and considerably smaller than spanning the
/// menu bar row.
public struct NotchSurfaceLayout: Sendable, Equatable {
    /// Width of one provider chip in the collapsed tab.
    ///
    /// A ring on its own by default. Showing figures alongside widens every chip, which is
    /// why it is a setting rather than always-on: the collapsed tab's whole job is to be
    /// small, and the ring's colour already answers "is my usage okay?".
    public let chipWidth: CGFloat
    /// Width of the trailing add button.
    public let addChipWidth: CGFloat
    /// Whether the add button is shown; hidden once the row is full.
    public let showsAddButton: Bool
    public let collapsedHeight: CGFloat
    public let horizontalPadding: CGFloat
    /// Outward flare where the tab meets the chrome above it.
    public let flare: CGFloat
    public let expandedWidth: CGFloat
    public let contentRowHeight: CGFloat
    public let contentRowSpacing: CGFloat
    public let cardTitleHeight: CGFloat
    public let bodyVerticalPadding: CGFloat
    /// How many providers are shown; the collapsed tab is only as wide as it needs to be.
    public let providerCount: Int

    /// Window rows reserved for the busiest provider, so switching never resizes the window.
    public static let maximumRows = 2

    public init(
        providerCount: Int,
        showsAddButton: Bool = true,
        chipWidth: CGFloat = 30,
        addChipWidth: CGFloat = 26,
        collapsedHeight: CGFloat = 30,
        horizontalPadding: CGFloat = 11,
        flare: CGFloat = 10,
        expandedWidth: CGFloat = 322,
        contentRowHeight: CGFloat = 42,
        contentRowSpacing: CGFloat = 9,
        cardTitleHeight: CGFloat = 20,
        bodyVerticalPadding: CGFloat = 11
    ) {
        self.providerCount = max(providerCount, 1)
        self.showsAddButton = showsAddButton
        self.chipWidth = chipWidth
        self.addChipWidth = addChipWidth
        self.collapsedHeight = collapsedHeight
        self.horizontalPadding = horizontalPadding
        self.flare = flare
        self.expandedWidth = expandedWidth
        self.contentRowHeight = contentRowHeight
        self.contentRowSpacing = contentRowSpacing
        self.cardTitleHeight = cardTitleHeight
        self.bodyVerticalPadding = bodyVerticalPadding
    }

    public var collapsedSize: CGSize {
        let chips = chipWidth * CGFloat(providerCount)
        let add = showsAddButton ? addChipWidth : 0
        return CGSize(
            width: chips + add + horizontalPadding * 2 + flare * 2,
            height: collapsedHeight
        )
    }

    /// Height of the expanded body, following the content it actually holds.
    ///
    /// The collapsed chip row stays put when the tab expands and doubles as the provider
    /// switcher, so the body holds only the detail card. A provider reporting one window
    /// must not reserve the room a two-window provider needs, or the tab opens onto empty
    /// space.
    public func expandedBodyHeight(rowCount: Int) -> CGFloat {
        let rows = max(rowCount, 1)
        let rowsHeight = CGFloat(rows) * contentRowHeight
            + CGFloat(rows - 1) * contentRowSpacing
        // The trailing `contentRowSpacing` is the gap between the title and the first row.
        // Omitting it is what made rows overlap: the panel was a full gap too short.
        return bodyVerticalPadding * 2 + cardTitleHeight + contentRowSpacing + rowsHeight
    }

    public func expandedSize(rowCount: Int) -> CGSize {
        CGSize(
            width: max(expandedWidth, collapsedSize.width),
            height: collapsedHeight + expandedBodyHeight(rowCount: rowCount)
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
