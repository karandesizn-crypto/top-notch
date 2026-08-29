import Foundation
import SideNotchCore

/// Resolves the surface's current size.
///
/// Shared by the view that draws the shape and the window that hit-tests it. If those two
/// disagreed, the surface would either swallow clicks outside itself or ignore clicks on
/// its own content, so both read from here.
enum SurfaceSizing {
    /// Chip width with a ring only, and with a figure beside it.
    static let ringOnlyChipWidth: CGFloat = 30
    static let chipWidthWithFigure: CGFloat = 58

    static func layout(
        providerCount: Int, notch: NotchMetrics, showsFigures: Bool, showsAddButton: Bool
    ) -> NotchSurfaceLayout {
        NotchSurfaceLayout(
            providerCount: providerCount,
            notchWidth: notch.notchWidth,
            notchHeight: notch.notchHeight,
            showsAddButton: showsAddButton,
            chipWidth: showsFigures ? chipWidthWithFigure : ringOnlyChipWidth,
            flare: Tokens.Surface.flare
        )
    }

    /// Number of window rows the expanded body will render for a provider.
    static func rowCount(for status: ProviderStatus?) -> Int {
        guard let windows = status?.snapshot?.windows, !windows.isEmpty else { return 1 }
        return min(windows.count, NotchSurfaceLayout.maximumRows)
    }

    static func size(
        layout: NotchSurfaceLayout, expanded: Bool, status: ProviderStatus?
    ) -> CGSize {
        layout.size(expanded: expanded, rowCount: rowCount(for: status))
    }
}
