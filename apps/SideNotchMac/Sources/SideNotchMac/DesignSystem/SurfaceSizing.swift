import Foundation
import SideNotchCore

/// Resolves the surface's current size.
///
/// Shared by the view that draws the shape and the window that hit-tests it. If those two
/// disagreed, the surface would either swallow clicks outside itself or ignore clicks on
/// its own content, so both read from here.
enum SurfaceSizing {
    static func layout(
        providerCount: Int, notch: NotchMetrics, showsFigures: Bool, showsAddButton: Bool
    ) -> NotchSurfaceLayout {
        NotchSurfaceLayout(
            providerCount: providerCount,
            notchWidth: notch.notchWidth,
            housingRowHeight: notch.notchHeight,
            showsAddButton: showsAddButton,
            // A figure beside the ring widens every chip, and the strip with it.
            chipWidth: showsFigures ? Tokens.Ring.chipWidthWithFigure : Tokens.Ring.chipWidth,
            flare: Tokens.Surface.flare
        )
    }

    static func size(
        layout: NotchSurfaceLayout, expanded: Bool, minimized: Bool
    ) -> CGSize {
        layout.size(expanded: expanded, minimized: minimized)
    }
}
