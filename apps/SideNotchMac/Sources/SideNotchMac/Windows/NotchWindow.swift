import AppKit

/// The window hosting the notch surface.
///
/// Sits at status-bar level so it can occupy the menu bar row and merge with the camera
/// housing; anything lower would be drawn under the menu bar and break the illusion. It is
/// safe to overlay there because the housing itself is a region the menu bar never uses,
/// and everything outside the drawn surface is click-through.
final class NotchWindow: NSPanel {
    /// Set while the surface is pinned open, so Escape and clicks reach it.
    var acceptsKey = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        // The surface draws its own shadow; a window shadow would trace the full
        // rectangle and give away that this is a window.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    /// Only while pinned: an ambient surface must never steal focus from the editor the
    /// user is working in.
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

/// Content view that passes clicks through everywhere the surface is not drawn.
///
/// The window is always sized for the expanded surface so that expanding needs no window
/// resize. Without this, the collapsed surface would swallow clicks across a wide band of
/// the menu bar.
final class PassthroughContentView: NSView {
    /// The live surface rectangle, in window coordinates.
    var interactiveRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect().contains(point) else { return nil }
        return super.hitTest(point)
    }
}
