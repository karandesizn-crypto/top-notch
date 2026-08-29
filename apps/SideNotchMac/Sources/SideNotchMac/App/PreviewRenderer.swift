import SwiftUI
import AppKit
import SideNotchCore

/// Renders the notch surface offscreen to a PNG.
///
/// Checking the live window needs screen-recording permission and a person at the keyboard;
/// `ImageRenderer` needs neither, so the surface stays verifiable from a build script. The
/// backdrop imitates the top of a display — a wallpaper strip with the dark chrome and the
/// camera housing drawn in — because the silhouette only makes sense against what it hangs
/// from.
@MainActor
enum PreviewRenderer {
    static func render(
        to path: String,
        store: UsageStore,
        settings: AppSettings,
        notch: NotchMetrics,
        selected: ProviderID?,
        expanded: Bool
    ) {
        let layout = SurfaceSizing.layout(providerCount: store.visibleProviders.count)

        let state = NotchSurfaceState()
        state.isExpanded = expanded
        state.isPinned = expanded
        state.selected = selected ?? store.visibleProviders.first ?? .codex

        let canvasWidth: CGFloat = 760
        let chromeHeight = notch.notchHeight
        let canvasHeight = chromeHeight + layout.maximumExpandedSize.height + 70

        let content = ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.30, blue: 0.46),
                    Color(red: 0.36, green: 0.20, blue: 0.42),
                    Color(red: 0.62, green: 0.28, blue: 0.24),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // The chrome the tab hangs from: the menu bar row, with the camera housing
            // drawn opaque at its centre.
            VStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(notch.hasPhysicalNotch ? 0.92 : 0.55))
                        .frame(height: chromeHeight)
                    if notch.hasPhysicalNotch {
                        Rectangle()
                            .fill(.black)
                            .frame(width: notch.notchWidth, height: chromeHeight)
                    }
                }
                NotchRootView(store: store, settings: settings, surface: state, layout: layout)
                Spacer(minLength: 0)
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
