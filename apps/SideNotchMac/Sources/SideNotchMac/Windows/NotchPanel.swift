import AppKit

/// Borderless, transparent panel that hosts the rail.
///
/// Non-activating so hovering or clicking the rail never steals focus from the editor the
/// user is actually working in — the whole point of the product is not interrupting them.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false          // Shapes draw their own; a window shadow would box them.
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Content view that lets clicks through wherever the rail is not actually drawn.
///
/// The panel is always full width so the card can appear without a window resize, but most
/// of that width is empty when nothing is focused. Without this, the panel would silently
/// eat clicks on whatever sits behind the empty region.
final class PassthroughContentView: NSView {
    /// Interactive region, in window coordinates.
    var interactiveRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect().contains(point) else { return nil }
        return super.hitTest(point)
    }
}
