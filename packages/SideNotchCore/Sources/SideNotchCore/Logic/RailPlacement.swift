import Foundation
import CoreGraphics

/// Where the rail panel sits on a given display.
///
/// Pure arithmetic over screen rectangles, kept out of the window controller so it can be
/// tested for the cases that are painful to reproduce by hand: notched displays, external
/// monitors with a negative origin, and screens shorter than the rail.
public enum RailPlacement {

    /// Computes the panel frame in AppKit screen coordinates, where the origin is
    /// bottom-left and y grows upward.
    ///
    /// - Parameters:
    ///   - screenFrame: the display's full frame.
    ///   - visibleFrame: the display's frame minus the menu bar and Dock.
    ///   - panelSize: the rail's size.
    ///   - topInset: gap below the menu bar.
    ///
    /// On a notched Mac the menu bar is as tall as the notch housing, so `visibleFrame`
    /// already excludes it and no separate notch handling is needed — anchoring to
    /// `visibleFrame.maxY` is correct on both notched and non-notched displays. That is why
    /// safe-area insets are not consulted here.
    public static func frame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        panelSize: CGSize,
        topInset: CGFloat
    ) -> CGRect {
        let x = screenFrame.maxX - panelSize.width

        let preferredY = visibleFrame.maxY - topInset - panelSize.height
        // Never push the rail below the bottom of the display; on a screen too short for
        // the full rail, favour keeping the top visible since that is where the first
        // providers are.
        let lowestAllowed = screenFrame.minY
        let y = max(preferredY, lowestAllowed)

        return CGRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    /// Whether a display has a camera housing cutting into its top edge.
    ///
    /// Only meaningful for deciding presentation style; placement does not need it.
    public static func hasNotch(safeAreaTopInset: CGFloat) -> Bool {
        safeAreaTopInset > 0
    }
}
