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
    /// False when no attached display is a suitable home for the surface, in which case it
    /// is hidden rather than parked at some display's top edge.
    private(set) var hasSuitableDisplay: Bool = false

    /// Called after any change, so the window can re-pin itself.
    var onChange: (() -> Void)?

    /// Only ever mutated on the main actor; declared nonisolated so `deinit` can unhook
    /// the observers, which block-based observers do not do for themselves.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    /// Whether displays without a housing are acceptable. Supplied by settings.
    private let allowsDisplaysWithoutNotch: () -> Bool

    init(allowsDisplaysWithoutNotch: @escaping () -> Bool = { false }) {
        self.allowsDisplaysWithoutNotch = allowsDisplaysWithoutNotch
        // Computed into locals first: @Observable routes property reads through accessors,
        // which are unavailable until every stored property is initialized.
        let resolved = Self.resolve(allowingWithoutNotch: allowsDisplaysWithoutNotch())
        display = resolved.metrics
        notch = NotchPlacement.metrics(for: resolved.metrics)
        hasSuitableDisplay = resolved.isSuitable
        observeEnvironment()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Recomputes from the current screens. Safe to call often; only reports real changes.
    func refresh() {
        let resolved = Self.resolve(allowingWithoutNotch: allowsDisplaysWithoutNotch())
        let newNotch = NotchPlacement.metrics(for: resolved.metrics)

        guard resolved.metrics != display || newNotch != notch
            || resolved.isSuitable != hasSuitableDisplay else { return }

        display = resolved.metrics
        notch = newNotch
        hasSuitableDisplay = resolved.isSuitable
        Log.app.debug("display changed: suitable \(resolved.isSuitable ? "yes" : "no")")
        onChange?()
    }

    /// Chooses the display for the surface, deferring the rule itself to `NotchPlacement`
    /// so it stays testable away from AppKit.
    private static func resolve(
        allowingWithoutNotch: Bool
    ) -> (metrics: DisplayMetrics, isSuitable: Bool) {
        let screens = NSScreen.screens
        let all = screens.map { metrics(for: $0) }
        let mainIndex = NSScreen.main.flatMap { screens.firstIndex(of: $0) }

        guard let index = NotchPlacement.preferredDisplayIndex(
            among: all, mainIndex: mainIndex, allowingDisplaysWithoutNotch: allowingWithoutNotch
        ) else {
            // Keep the last known geometry so the window has something coherent to sit on
            // while hidden; `isSuitable` is what actually gates visibility.
            return (all.first ?? metrics(for: nil), false)
        }
        return (all[index], true)
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
