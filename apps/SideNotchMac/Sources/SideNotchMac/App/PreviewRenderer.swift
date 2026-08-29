import SwiftUI
import AppKit
import SideNotchCore

/// Renders the notch surface offscreen to a PNG.
///
/// Checking the live window needs screen-recording permission and a person at the keyboard;
/// `ImageRenderer` needs neither, so the surface stays verifiable from a build script.
/// The backdrop imitates the top of a display — a wallpaper strip with the physical camera
/// housing drawn in — because the silhouette only makes sense against what it merges into.
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
        let layout = SurfaceSizing.layout(for: notch)

        let state = NotchSurfaceState()
        state.isExpanded = expanded
        state.isPinned = expanded
        if let selected { state.selected = selected }

        let canvasWidth: CGFloat = 900
        let canvasHeight = layout.maximumExpandedSize.height + 90

        let content = ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.30, blue: 0.46),
                    Color(red: 0.36, green: 0.20, blue: 0.42),
                    Color(red: 0.62, green: 0.28, blue: 0.24),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // The physical housing: opaque hardware the surface has to reserve room for.
            if notch.hasPhysicalNotch {
                Rectangle()
                    .fill(.black)
                    .frame(width: notch.notchWidth, height: notch.notchHeight)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            NotchRootView(store: store, settings: settings, surface: state, layout: layout)
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
