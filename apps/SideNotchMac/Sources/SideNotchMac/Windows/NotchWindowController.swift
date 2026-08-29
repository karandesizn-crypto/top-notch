import AppKit
import SwiftUI
import SideNotchCore
import ProviderKit

/// Owns the notch window: sizes it from the display's measured housing, keeps it pinned to
/// the top-centre of the active display, and follows every change that can invalidate that.
@MainActor
final class NotchWindowController {
    private let window: NotchWindow
    private let store: UsageStore
    private let settings: AppSettings
    private let placement: DisplayPlacementService
    private let surface = NotchSurfaceState()
    private var hosting: NSHostingView<NotchHost>?
    private var escapeMonitor: Any?

    var windowFrame: NSRect { window.frame }
    var notch: NotchMetrics { placement.notch }

    /// Opens settings so another tool can be added; wired by the app delegate.
    var onAddProvider: (() -> Void)?

    init(store: UsageStore, settings: AppSettings, placement: DisplayPlacementService) {
        self.store = store
        self.settings = settings
        self.placement = placement

        let layout = Self.layout(store: store, settings: settings, placement: placement)
        window = NotchWindow(contentRect: NSRect(origin: .zero, size: layout.windowSize))

        let container = PassthroughContentView(
            frame: NSRect(origin: .zero, size: layout.windowSize)
        )
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(
            rootView: NotchHost(
                store: store, settings: settings, surface: surface, layout: layout,
                onAddProvider: { }
            )
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        self.hosting = hosting

        // AppKit window coordinates: origin bottom-left. The surface is top-centred inside
        // the window, so its rect follows the current state's size.
        container.interactiveRect = { [weak self] in
            guard let self else { return .zero }
            let windowSize = window.frame.size
            let layout = currentLayout()
            let size = SurfaceSizing.size(
                layout: layout,
                expanded: surface.isExpanded,
                status: store.status(for: surface.selected)
            )
            return CGRect(
                x: (windowSize.width - size.width) / 2,
                y: windowSize.height - size.height,
                width: size.width,
                height: size.height
            )
        }

        window.contentView = container

        placement.onChange = { [weak self] in self?.applyPlacement() }
    }

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    func show() {
        applyAppearance()
        applyPlacement()
        installEscapeMonitor()
    }

    func hide() { window.orderOut(nil) }

    func applyAppearance() {
        window.appearance = settings.appearance.nsAppearance
    }

    /// Re-derives size and position from the current display.
    ///
    /// Called on launch and on every display change; a resolution or scaling change alters
    /// the housing's measured size, so the window is resized as well as moved.
    func applyPlacement() {
        // No suitable display means no surface at all. Parking it at some display's top
        // edge with nothing to attach to reads as a bug, and the menu bar item remains the
        // way in.
        guard placement.hasSuitableDisplay else {
            window.orderOut(nil)
            return
        }

        let layout = currentLayout()
        let frame = NotchPlacement.surfaceFrame(
            size: layout.windowSize, metrics: placement.notch, display: placement.display
        )
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        hosting?.rootView = NotchHost(
            store: store, settings: settings, surface: surface, layout: layout,
            onAddProvider: { [weak self] in self?.onAddProvider?() }
        )
    }

    /// Selects the provider the collapsed surface shows.
    func selectProvider(_ provider: ProviderID) {
        surface.selected = provider
    }

    /// Ensures the selected provider is one that is actually visible.
    func reconcileSelection() {
        let visible = store.visibleProviders
        guard !visible.isEmpty else { return }
        if !visible.contains(surface.selected) {
            surface.selected = visible.first!
        }
    }

    func collapse() {
        surface.isPinned = false
        surface.isExpanded = false
    }

    /// Escape collapses a pinned surface.
    ///
    /// A local monitor is enough: the window only becomes key while pinned, which is the
    /// only state Escape needs to act on.
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, surface.isPinned, event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                withAnimation(Tokens.Motion.surface(reduceMotion: false)) { self.collapse() }
            }
            return nil
        }
    }

    /// Layout for the current provider count and preferences.
    ///
    /// Static so the initializer can call it before `self` exists.
    private static func layout(
        store: UsageStore, settings: AppSettings, placement: DisplayPlacementService
    ) -> NotchSurfaceLayout {
        SurfaceSizing.layout(
            providerCount: store.visibleProviders.count,
            notch: placement.notch,
            showsFigures: settings.showPercentages,
            showsAddButton: settings.canAddProvider
        )
    }

    private func currentLayout() -> NotchSurfaceLayout {
        Self.layout(store: store, settings: settings, placement: placement)
    }

    /// Placement summary, for verifying multi-display behaviour without a screenshot.
    func placementDescription() -> String {
        let notch = placement.notch
        let display = placement.display
        let layout = currentLayout()
        var lines: [String] = []
        lines.append("screens        \(NSScreen.screens.count)")
        lines.append("display        \(Int(display.frame.width))x\(Int(display.frame.height)) @\(display.backingScaleFactor)x")
        lines.append("physical notch \(notch.hasPhysicalNotch ? "yes" : "no")")
        lines.append("surface shown  \(placement.hasSuitableDisplay ? "yes" : "no")")
        lines.append("housing        \(notch.notchWidth)x\(notch.notchHeight) centred at x=\(notch.centerX)")
        lines.append("anchor top y   \(notch.anchorTopY)")
        lines.append("providers      \(store.visibleProviders.count)")
        lines.append("collapsed      \(Int(layout.collapsedSize.width))x\(Int(layout.collapsedSize.height))")
        lines.append("expanded max   \(Int(layout.maximumExpandedSize.width))x\(Int(layout.maximumExpandedSize.height))")
        lines.append("window         \(Int(window.frame.width))x\(Int(window.frame.height)) at (\(Int(window.frame.minX)), \(Int(window.frame.minY)))")
        lines.append("window top     \(Int(window.frame.maxY))  display top \(Int(display.frame.maxY))")
        return lines.joined(separator: "\n")
    }
}

/// Bridges the observable state into SwiftUI.
struct NotchHost: View {
    let store: UsageStore
    let settings: AppSettings
    @Bindable var surface: NotchSurfaceState
    let layout: NotchSurfaceLayout
    let onAddProvider: () -> Void

    var body: some View {
        NotchRootView(
            store: store, settings: settings, surface: surface,
            layout: layout, onAddProvider: onAddProvider
        )
    }
}
