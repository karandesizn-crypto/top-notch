import AppKit
import SwiftUI
import SideNotchCore

/// Owns the rail panel, keeps it on the right display, and follows display changes.
@MainActor
final class RailWindowController {
    private let panel: NotchPanel
    private let store: UsageStore
    private let settings: AppSettings
    private let state = RailState()
    private var container: PassthroughContentView?
    private var observers: [NSObjectProtocol] = []

    /// Panel size follows the number of visible providers, so disabling one shrinks the
    /// rail instead of leaving a gap.
    static func panelSize(providerCount: Int) -> CGSize {
        CGSize(
            width: Tokens.Card.width + Tokens.Card.railGap + Tokens.Rail.width,
            height: Tokens.Rail.panelHeight(itemCount: max(providerCount, 1))
        )
    }

    var panelFrame: NSRect { panel.frame }

    init(store: UsageStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        let size = Self.panelSize(providerCount: store.visibleProviders.count)
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: size))

        let container = PassthroughContentView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(
            rootView: RailHost(store: store, settings: settings, state: state)
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        // AppKit window coordinates: origin bottom-left. The rail always occupies the
        // right-hand strip; with a card showing, the whole panel is interactive. Everything
        // else stays click-through so the desktop behind keeps working.
        container.interactiveRect = { [weak self] in
            guard let self else { return .zero }
            let size = panel.frame.size
            guard state.focused == nil else { return CGRect(origin: .zero, size: size) }
            return CGRect(
                x: size.width - Tokens.Rail.width, y: 0,
                width: Tokens.Rail.width, height: size.height
            )
        }

        panel.contentView = container
        self.container = container

        observeScreenChanges()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func show() {
        applyAppearance()
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func applyAppearance() {
        panel.appearance = settings.appearance.nsAppearance
    }

    /// Resizes for the current provider count and re-pins to the active display.
    func reposition() {
        guard let screen = targetScreen() else { return }
        let size = Self.panelSize(providerCount: store.visibleProviders.count)
        let frame = RailPlacement.frame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            panelSize: size,
            topInset: Tokens.Rail.topInset
        )
        panel.setFrame(frame, display: true)
    }

    /// The display the rail should live on: the one with the menu bar and keyboard focus,
    /// falling back to the first attached screen if the system reports none.
    private func targetScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    /// Re-pins on display reconfiguration and on wake.
    ///
    /// Unplugging a monitor otherwise strands the panel at coordinates that no longer
    /// exist, leaving an invisible rail.
    private func observeScreenChanges() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            }
        )
    }

    /// Placement summary, for verifying multi-display behaviour without a screenshot.
    func placementDescription() -> String {
        guard let screen = targetScreen() else { return "no screen" }
        let frame = panel.frame
        let notch = RailPlacement.hasNotch(safeAreaTopInset: screen.safeAreaInsets.top)
        var lines: [String] = []
        lines.append("screens      \(NSScreen.screens.count)")
        lines.append("display      \(Int(screen.frame.width))x\(Int(screen.frame.height)) notch: \(notch)")
        lines.append("panel        \(Int(frame.width))x\(Int(frame.height)) at (\(Int(frame.minX)), \(Int(frame.minY)))")
        lines.append("right edge   panel \(Int(frame.maxX)) vs display \(Int(screen.frame.maxX))")
        lines.append("top gap      \(Int(screen.visibleFrame.maxY - frame.maxY))pt below the menu bar")
        return lines.joined(separator: "\n")
    }
}

/// Focus state shared between the SwiftUI tree and the controller's hit testing.
@Observable
@MainActor
final class RailState {
    var focused: ProviderID?
}

private struct RailHost: View {
    let store: UsageStore
    let settings: AppSettings
    @Bindable var state: RailState

    var body: some View {
        RailView(store: store, settings: settings, focused: $state.focused)
    }
}
