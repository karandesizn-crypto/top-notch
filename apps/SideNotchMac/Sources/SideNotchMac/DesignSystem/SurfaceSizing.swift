import Foundation
import SideNotchCore

/// Resolves the surface's current size.
///
/// Shared by the view that draws the shape and the window that hit-tests it. If these two
/// ever disagreed, the surface would either swallow clicks outside itself or ignore clicks
/// on its own content, so they read from one function.
enum SurfaceSizing {
    static func layout(for notch: NotchMetrics) -> NotchSurfaceLayout {
        NotchSurfaceLayout(
            notch: notch,
            flare: Tokens.Surface.flare,
            collapsedFlank: Tokens.Surface.collapsedFlank,
            expandedFlank: Tokens.Surface.expandedFlank,
            minimumRowHeight: Tokens.Surface.minimumRowHeight
        )
    }

    /// Number of window rows the expanded body will render for a provider.
    static func rowCount(for status: ProviderStatus?) -> Int {
        guard let windows = status?.snapshot?.windows, !windows.isEmpty else { return 1 }
        return min(windows.count, NotchSurfaceLayout.maximumRows)
    }

    static func size(
        layout: NotchSurfaceLayout,
        expanded: Bool,
        status: ProviderStatus?,
        providerCount: Int
    ) -> CGSize {
        layout.size(
            expanded: expanded,
            rowCount: rowCount(for: status),
            hasSwitcher: providerCount > 1
        )
    }
}
