import Foundation
import CoreGraphics

/// Sizes for the notch surface in each state.
///
/// Kept in Core, and driven by the hardware's measured housing rather than constants, so
/// the same layout works on a 185pt notch, a wider one, or none at all. The window
/// controller and the view both read these, which is what keeps the drawn shape and the
/// window's hit region in agreement.
public struct NotchSurfaceLayout: Sendable, Equatable {
    /// Width of the physical housing. Zero on displays without one, which collapses the
    /// two flanks into one continuous strip.
    public let notchWidth: CGFloat
    /// Height of the housing row.
    public let notchHeight: CGFloat
    /// Outward flare where the surface meets the top of the display.
    public let flare: CGFloat
    public let collapsedFlank: CGFloat
    public let expandedFlank: CGFloat
    /// Floor for the housing row, for displays with no housing height to borrow.
    public let minimumRowHeight: CGFloat
    /// Height of one usage-window row in the expanded body.
    public let contentRowHeight: CGFloat
    public let contentRowSpacing: CGFloat
    /// Height of the provider switcher, when more than one provider is shown.
    public let switcherHeight: CGFloat
    public let bodyVerticalPadding: CGFloat
    /// The expanded body is never shorter than this, so the usage ring always fits.
    public let minimumBodyHeight: CGFloat
    /// Rows the window reserves space for. The window is sized once, for the busiest
    /// provider, so switching providers never resizes it mid-animation.
    public static let maximumRows = 2

    public init(
        notchWidth: CGFloat,
        notchHeight: CGFloat,
        flare: CGFloat,
        collapsedFlank: CGFloat,
        expandedFlank: CGFloat,
        minimumRowHeight: CGFloat,
        contentRowHeight: CGFloat = 48,
        contentRowSpacing: CGFloat = 10,
        switcherHeight: CGFloat = 36,
        bodyVerticalPadding: CGFloat = 14,
        minimumBodyHeight: CGFloat = 78
    ) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.flare = flare
        self.collapsedFlank = collapsedFlank
        self.expandedFlank = expandedFlank
        self.minimumRowHeight = minimumRowHeight
        self.contentRowHeight = contentRowHeight
        self.contentRowSpacing = contentRowSpacing
        self.switcherHeight = switcherHeight
        self.bodyVerticalPadding = bodyVerticalPadding
        self.minimumBodyHeight = minimumBodyHeight
    }

    public init(notch: NotchMetrics, flare: CGFloat, collapsedFlank: CGFloat,
                expandedFlank: CGFloat, minimumRowHeight: CGFloat) {
        self.init(
            notchWidth: notch.notchWidth,
            notchHeight: notch.notchHeight,
            flare: flare,
            collapsedFlank: collapsedFlank,
            expandedFlank: expandedFlank,
            minimumRowHeight: minimumRowHeight
        )
    }

    /// Height of the row alongside the housing.
    public var rowHeight: CGFloat { max(notchHeight, minimumRowHeight) }

    public var collapsedSize: CGSize {
        CGSize(width: notchWidth + collapsedFlank * 2 + flare * 2, height: rowHeight)
    }

    /// Height of the expanded body for the content it actually holds.
    ///
    /// Driven by the row count rather than fixed, because providers differ: Codex reports
    /// one window on some plans and two on others, and a fixed height leaves a void under
    /// the single-window case.
    public func expandedBodyHeight(rowCount: Int, hasSwitcher: Bool) -> CGFloat {
        let rows = max(rowCount, 1)
        let rowsHeight = CGFloat(rows) * contentRowHeight
            + CGFloat(rows - 1) * contentRowSpacing
        let switcher = hasSwitcher ? switcherHeight : 0
        let total = bodyVerticalPadding * 2 + rowsHeight + switcher
        return max(total, minimumBodyHeight + switcher)
    }

    public func expandedSize(rowCount: Int, hasSwitcher: Bool) -> CGSize {
        CGSize(
            width: notchWidth + expandedFlank * 2 + flare * 2,
            height: rowHeight + expandedBodyHeight(rowCount: rowCount, hasSwitcher: hasSwitcher)
        )
    }

    /// The largest the surface can get, which is what the window is sized for.
    public var maximumExpandedSize: CGSize {
        expandedSize(rowCount: Self.maximumRows, hasSwitcher: true)
    }

    public func size(expanded: Bool, rowCount: Int, hasSwitcher: Bool) -> CGSize {
        expanded ? expandedSize(rowCount: rowCount, hasSwitcher: hasSwitcher) : collapsedSize
    }

    /// Size of the hosting window: the largest state, so expanding never resizes the
    /// window. The surface is drawn inside it and hit testing follows the drawn shape,
    /// which keeps the animation entirely in SwiftUI.
    public var windowSize: CGSize { maximumExpandedSize }

    /// Content width available on one side of the housing, in the given state.
    public func flankWidth(expanded: Bool) -> CGFloat {
        expanded ? expandedFlank : collapsedFlank
    }
}
