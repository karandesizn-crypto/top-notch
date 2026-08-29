import AppKit
import Observation
import SideNotchCore
import ProviderKit

/// Resolves which display the notch surface belongs on, and republishes its metrics
/// whenever the display environment changes.
///
/// Every value comes from `NSScreen`; nothing about notch size, menu bar height, or screen
/// resolution is assumed. The service is the only place that touches `NSScreen`, so the
/// geometry in `NotchPlacement` stays testable.
@Observable
@MainActor
final class DisplayPlacementService {
    private(set) var display: DisplayMetrics
    private(set) var notch: NotchMetrics

    /// Called after any change, so the window can re-pin itself.
    var onChange: (() -> Void)?

    /// Only ever mutated on the main actor; declared nonisolated so `deinit` can unhook
    /// the observers, which block-based observers do not do for themselves.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    init() {
        // Computed into locals first: @Observable routes property reads through accessors,
        // which are unavailable until every stored property is initialized.
        let metrics = Self.metrics(for: Self.preferredScreen())
        display = metrics
        notch = NotchPlacement.metrics(for: metrics)
        observeEnvironment()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Recomputes from the current screen. Safe to call often; only reports real changes.
    func refresh() {
        let screen = Self.preferredScreen()
        let newDisplay = Self.metrics(for: screen)
        let newNotch = NotchPlacement.metrics(for: newDisplay)

        guard newDisplay != display || newNotch != notch else { return }
        display = newDisplay
        notch = newNotch
        Log.app.debug("display changed: notch \(newNotch.hasPhysicalNotch ? "yes" : "no")")
        onChange?()
    }

    /// The display carrying the menu bar and keyboard focus.
    private static func preferredScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    private static func metrics(for screen: NSScreen?) -> DisplayMetrics {
        guard let screen else {
            // No attached display. Returning zeroes keeps the app alive until one appears.
            return DisplayMetrics(
                frame: .zero, visibleFrame: .zero, safeAreaTop: 0,
                auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil,
                menuBarHeight: NSStatusBar.system.thickness, backingScaleFactor: 2
            )
        }
        return DisplayMetrics(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: NSStatusBar.system.thickness,
            backingScaleFactor: screen.backingScaleFactor
        )
    }

    /// Watches every event that can invalidate placement.
    ///
    /// Resolution and scaling changes, monitor hot-plug, and display sleep all arrive as
    /// `didChangeScreenParameters`; wake and Space switches need their own workspace
    /// notifications. Missing any of these strands the surface at coordinates that no
    /// longer exist.
    private func observeEnvironment() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        )

        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.screensDidWakeNotification,
        ] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            )
        }
    }
}
