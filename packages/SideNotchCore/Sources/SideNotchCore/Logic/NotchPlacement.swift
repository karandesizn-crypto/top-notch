import Foundation
import CoreGraphics

/// What SideNotch needs to know about one display.
///
/// A plain value rather than an `NSScreen`, so placement can be computed and tested for
/// displays that are not attached — notched built-ins, external monitors at negative
/// origins, scaled resolutions.
public struct DisplayMetrics: Sendable, Equatable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`. Non-zero exactly when a camera housing intrudes.
    public let safeAreaTop: CGFloat
    /// Width of `auxiliaryTopLeftArea`; nil on displays without a housing.
    public let auxiliaryTopLeftWidth: CGFloat?
    public let auxiliaryTopRightWidth: CGFloat?
    /// Menu bar height, used as the anchor on displays with no housing.
    public let menuBarHeight: CGFloat
    public let backingScaleFactor: CGFloat

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        menuBarHeight: CGFloat,
        backingScaleFactor: CGFloat
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
        self.menuBarHeight = menuBarHeight
        self.backingScaleFactor = backingScaleFactor
    }
}

/// The physical notch, resolved into numbers the surface can be built around.
public struct NotchMetrics: Sendable, Equatable {
    /// True when the display actually has a camera housing.
    public let hasPhysicalNotch: Bool
    /// Width of the housing. Zero on displays without one.
    public let notchWidth: CGFloat
    /// Height of the region the surface treats as "the notch row".
    ///
    /// On a notched display this is the safe-area inset, which is taller than the menu bar
    /// (32pt versus 22pt on the machine this was measured on) — content must clear the
    /// housing, not just the menu bar.
    public let notchHeight: CGFloat
    /// Horizontal centre of the housing, in screen coordinates.
    public let centerX: CGFloat
    /// The y the surface's top edge anchors to, in AppKit screen coordinates.
    ///
    /// The surface hangs *below* the top chrome rather than straddling it: on a notched
    /// display that is the bottom edge of the camera housing, and without a housing it is
    /// the bottom of the menu bar. Both read as the dark strip above continuing downward,
    /// and neither covers menu bar items.
    public let anchorTopY: CGFloat
    public let backingScaleFactor: CGFloat

    /// Horizontal span of the housing in screen coordinates.
    public var notchMinX: CGFloat { centerX - notchWidth / 2 }
    public var notchMaxX: CGFloat { centerX + notchWidth / 2 }
}

/// Positions the notch surface on a display.
///
/// All geometry is derived from the display's reported safe area and auxiliary top areas.
/// Nothing here assumes a particular Mac model, notch size, or resolution.
public enum NotchPlacement {

    public static func metrics(for display: DisplayMetrics) -> NotchMetrics {
        let hasNotch = display.safeAreaTop > 0
            && display.auxiliaryTopLeftWidth != nil
            && display.auxiliaryTopRightWidth != nil

        guard hasNotch,
              let left = display.auxiliaryTopLeftWidth,
              let right = display.auxiliaryTopRightWidth
        else {
            return NotchMetrics(
                hasPhysicalNotch: false,
                notchWidth: 0,
                notchHeight: display.menuBarHeight,
                centerX: display.frame.midX,
                anchorTopY: display.visibleFrame.maxY,
                backingScaleFactor: display.backingScaleFactor
            )
        }

        // The housing is whatever the two auxiliary areas do not cover.
        let notchWidth = max(0, display.frame.width - left - right)
        // Derived from the left area's width rather than assumed to be the screen centre:
        // the two areas are equal on current hardware, but nothing guarantees that.
        let centerX = display.frame.minX + left + notchWidth / 2

        return NotchMetrics(
            hasPhysicalNotch: true,
            notchWidth: notchWidth,
            notchHeight: display.safeAreaTop,
            centerX: centerX,
            // Below the housing, not the top of the display.
            anchorTopY: display.frame.maxY - display.safeAreaTop,
            backingScaleFactor: display.backingScaleFactor
        )
    }

    /// Frame for a surface of `size`, centred on the notch and hanging from the anchor.
    ///
    /// Clamped horizontally so a surface wider than the display, or a notch near an edge on
    /// unusual hardware, still produces an on-screen window.
    public static func surfaceFrame(
        size: CGSize, metrics: NotchMetrics, display: DisplayMetrics
    ) -> CGRect {
        let idealX = metrics.centerX - size.width / 2
        let minX = display.frame.minX
        let maxX = display.frame.maxX - size.width
        let x = maxX >= minX ? min(max(idealX, minX), maxX) : minX

        let y = metrics.anchorTopY - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Rounds a length to whole pixels on the display, so edges and hairlines stay crisp
    /// on Retina rather than landing on a half pixel.
    public static func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value.rounded() }
        return (value * scale).rounded() / scale
    }
}
