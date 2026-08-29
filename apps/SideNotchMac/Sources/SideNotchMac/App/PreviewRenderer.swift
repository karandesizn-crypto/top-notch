import SwiftUI
import AppKit
import SideNotchCore

/// Renders the rail offscreen to a PNG.
///
/// Checking the live panel needs screen-recording permission and a person at the keyboard;
/// `ImageRenderer` needs neither, so the interface stays verifiable from a build script.
@MainActor
enum PreviewRenderer {
    static func render(
        to path: String, store: UsageStore, settings: AppSettings, focused: ProviderID?
    ) {
        let size = RailWindowController.panelSize(providerCount: store.visibleProviders.count)
        let content = ZStack {
            // Stands in for a wallpaper, so the black slab and its concave fillets show.
            LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.72, blue: 0.86),
                    Color(red: 0.85, green: 0.86, blue: 0.62),
                    Color(red: 0.90, green: 0.42, blue: 0.24),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RailView(store: store, settings: settings, focused: .constant(focused))
        }
        .frame(width: size.width, height: size.height)
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
