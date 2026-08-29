import Foundation
import SideNotchCore

/// Resolves the surface's current size.
///
/// Shared by the view that draws the shape and the window that hit-tests it. If those two
/// disagreed, the surface would either swallow clicks outside itself or ignore clicks on
/// its own content, so both read from here.
enum SurfaceSizing {
    static func layout(providerCount: Int) -> NotchSurfaceLayout {
        NotchSurfaceLayout(
            providerCount: providerCount,
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
