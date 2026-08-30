import AppKit
import SwiftUI
import SideNotchCore
import ProviderKit
import UsageKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var manager: UsageManager!
    /// Kept so the wake observer can be torn down on quit.
    private var wakeObserver: (any NSObjectProtocol)?
    private var controller: NotchWindowController!
    private var placement: DisplayPlacementService!
    private var notifications: NotificationService!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background utility: rail and menu bar only, no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        terminateOtherInstances()

        settings = AppSettings()
        notifications = NotificationService()

        // Fixture mode is debug-only, and the whole branch is compiled out of release
        // rather than left behind a `false` flag: a dead ternary emits "will never be
        // executed" on every release build, and warnings that are expected are warnings
        // nobody reads. A shipped build has no code path to fixture data at all.
        //
        // Fixture runs get an in-memory cache. Sharing the real one let a mock render write
        // figures that then outlived it, because a provider whose fetch fails keeps
        // whatever the cache last held.
        let cache: any UsageCaching
        let providerOverride: [any UsageProvider]?
        #if DEBUG
        if ProcessInfo.processInfo.environment["SIDENOTCH_MOCK"] == "1" {
            cache = InMemoryUsageCache()
            providerOverride = MockUsageProvider.showcase()
        } else {
            cache = FileUsageCache()
            providerOverride = nil
        }
        #else
        cache = FileUsageCache()
        providerOverride = nil
        #endif

        manager = UsageManager(
            settings: settings, cache: cache, notifications: notifications,
            providerOverride: providerOverride
        )
        placement = DisplayPlacementService { [weak self] in
            self?.settings.showsWithoutNotch ?? false
        }
        controller = NotchWindowController(
            manager: manager, settings: settings, placement: placement
        )
        controller.reconcileSelection()
        controller.onAddProvider = { [weak self] in self?.openSettings() }

        if handleDiagnosticModes() { return }

        applyAppearance()
        controller.show()
        installStatusItem()

        // Two independent tasks, deliberately not one sequential one.
        //
        // These were chained, which put an optional permission prompt in front of the
        // product's only job. `requestAuthorization` does not return until the user answers
        // the system dialog — so ignoring that dialog, or any stall in it, left the rail
        // permanently empty with the app running and apparently healthy. Reading usage must
        // not wait on permission to *notify* about usage.
        Task { await manager.start() }
        Task { await notifications.requestAuthorization() }

        observeWake()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Terminating the app-server child process matters: it outlives us otherwise.
        let manager = self.manager
        Task { await manager?.stop() }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Ends any other copy of this app that is already running, so the newest launch wins.
    ///
    /// LaunchServices normally prevents a second instance of a bundled app, but only for
    /// copies it knows about. A build left running from a path that has since been renamed
    /// or deleted keeps going indefinitely, invisible in the Dock because this app has no
    /// Dock icon — and was found doing exactly that on this machine, hours after its bundle
    /// had moved.
    ///
    /// Two instances is not a cosmetic problem. Both draw a notch surface, both hold a
    /// Codex app-server child process, and both poll independently — which doubles the
    /// request rate against an endpoint that rate-limits hard and stays limited for hours.
    /// The rate limiter is per-process, so it cannot see the other one.
    ///
    /// The newest launch wins rather than exiting, because the common case is a rebuild:
    /// what you want after installing a new build is the new build, not a silent refusal
    /// to start.
    private func terminateOtherInstances() {
        let others = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        guard !others.isEmpty else { return }
        Log.app.notice("terminating \(others.count) older instance(s)")
        for instance in others {
            // Ask politely first: a clean termination is what stops the app-server child
            // being orphaned, which `applicationWillTerminate` handles and a kill does not.
            instance.terminate()
        }
    }

    /// Re-reads usage the moment the machine wakes.
    ///
    /// `RefreshScheduler` already detects this from the wall clock, so this is about
    /// latency rather than correctness: without it the rail can show pre-sleep figures for
    /// up to half a minute after the lid opens, which is precisely when someone glances at
    /// it. Purely a trigger — no visual or layout behaviour is involved.
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer block is `Sendable`, so reaching `self.manager` — which is
            // main-actor isolated — has to happen inside a main-actor context rather than
            // in the block itself, even though the block is already delivered on `.main`.
            // `queue: .main` is a delivery guarantee the compiler cannot see.
            Task { @MainActor in
                guard let manager = self?.manager else { return }
                await manager.refreshAll(trigger: .wake)
            }
        }
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "Top Notch"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Top Notch", action: #selector(quit), keyEquivalent: "q")
            .target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func refreshNow() {
        Task { await manager.refreshAll() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settings: settings,
            manager: manager,
            onSettingsChanged: { [weak self] in self?.settingsDidChange() },
            onProvidersChanged: { [weak self] in self?.providersDidChange() }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Top Notch Settings"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.appearance = settings.appearance.nsAppearance
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Applies preference changes that affect windows rather than just rendering.
    private func settingsDidChange() {
        applyAppearance()
        controller.applyAppearance()
        controller.reconcileSelection()
        // Re-resolve first: the display rule itself may have changed.
        placement.refresh()
        controller.applyPlacement()
        settingsWindow?.appearance = settings.appearance.nsAppearance
        notifications.reset()
        Task { await manager.refreshAll() }
    }

    /// Rebuilds the provider list after one is added or removed, then re-lays the surface:
    /// the tab's width follows how many providers are shown.
    private func providersDidChange() {
        Task {
            await manager.rebuildProviders()
            controller.reconcileSelection()
            controller.applyPlacement()
            await manager.refreshAll()
        }
    }

    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    // MARK: Diagnostics

    /// Offscreen render and placement modes, used to verify the UI and window geometry
    /// without screen-recording permission. Returns true when the app should not continue
    /// to normal startup.
    private func handleDiagnosticModes() -> Bool {
        // The whole diagnostic surface is debug-only. These modes exist to verify the
        // design lock and window geometry offscreen, which is a development and CI job;
        // a release build has no business honouring them, and stripping them removes the
        // only paths that terminate the app from an environment variable.
        #if !DEBUG
        return false
        #else
        let environment = ProcessInfo.processInfo.environment

        if let path = environment["SIDENOTCH_RENDER"] {
            Task {
                await manager.refreshAll()
                let focused = environment["SIDENOTCH_RENDER_FOCUS"]
                    .flatMap(ProviderType.init(rawValue:))
                PreviewRenderer.render(
                    to: path, manager: manager, settings: settings,
                    notch: placement.notch, selected: focused,
                    expanded: environment["SIDENOTCH_RENDER_EXPANDED"] == "1"
                )
                NSApp.terminate(nil)
            }
            return true
        }

        if environment["SIDENOTCH_DIAGNOSE"] == "1" {
            controller.show()
            print(controller.placementDescription())
            NSApp.terminate(nil)
            return true
        }

        return false
        #endif
    }
}
