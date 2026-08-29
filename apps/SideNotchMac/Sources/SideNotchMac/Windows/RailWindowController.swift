import AppKit
import SwiftUI
import SideNotchCore

/// Owns the panel, keeps it pinned to the active display's right edge, and follows display
/// changes.
@MainActor
final class RailWindowController {
    private let panel: NotchPanel
    private let store: UsageStore
    private let state: RailState
    private var contentView: PassthroughContentView?

    static var panelSize: CGSize {
        CGSize(
            width: Tokens.Card.width + Tokens.Card.railGap + Tokens.Rail.width,
            height: Tokens.Rail.geometry(itemCount: ProviderID.allCases.count).panelHeight
        )
    }

    init(store: UsageStore) {
        self.store = store
        self.state = RailState()
        self.panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize)
        )

        let container = PassthroughContentView(frame: NSRect(origin: .zero, size: Self.panelSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(
            rootView: RailHost(store: store, state: state)
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        // AppKit window coordinates: origin is bottom-left. The rail always occupies the
        // right-hand strip; when a card is showing the whole panel is interactive.
        container.interactiveRect = { [weak self] in
            let size = self?.panel.frame.size ?? Self.panelSize
            guard let state = self?.state, state.focused == nil else {
                return CGRect(origin: .zero, size: size)
            }
            return CGRect(
                x: size.width - Tokens.Rail.width, y: 0,
                width: Tokens.Rail.width, height: size.height
            )
        }

        panel.contentView = container
        self.contentView = container

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    var panelFrame: NSRect { panel.frame }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    /// Pins the panel to the right edge of the screen that currently owns the menu bar,
    /// just below it. Called on launch and whenever displays change, so unplugging an
    /// external monitor moves the rail rather than stranding it off-screen.
    func reposition() {
        guard let screen = targetScreen() else { return }
        let size = Self.panelSize
        let origin = CGPoint(
            x: screen.frame.maxX - size.width,
            y: screen.visibleFrame.maxY - Tokens.Rail.topInset - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }
}

/// Observable focus state shared between the SwiftUI view and the window controller's
/// hit-testing.
@Observable
@MainActor
final class RailState {
    var focused: ProviderID?
}

/// Bridges the shared state into the SwiftUI tree.
private struct RailHost: View {
    let store: UsageStore
    @Bindable var state: RailState

    var body: some View {
        RailView(store: store, focused: $state.focused)
    }
}
