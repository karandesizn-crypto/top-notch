import SwiftUI
import AppKit
import SideNotchCore

/// Renders the rail offscreen to a PNG.
///
/// Verifying the silhouette, ring geometry, and card layout otherwise means eyeballing a
/// live panel, which needs screen-recording permission and a human at the keyboard.
/// `ImageRenderer` needs neither, so the design is checkable from a build script.
@MainActor
enum PreviewRenderer {
    static func render(to path: String, store: UsageStore, focused: ProviderID?) {
        let size = RailWindowController.panelSize
        let state = RailState()
        state.focused = focused

        // A backdrop stands in for a wallpaper so the black slab and its concave fillets
        // are actually visible in the output.
        let content = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.72, blue: 0.86),
                    Color(red: 0.85, green: 0.86, blue: 0.62),
                    Color(red: 0.90, green: 0.42, blue: 0.24),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RailView(store: store, focused: .constant(focused))
        }
        .frame(width: size.width, height: size.height)

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
