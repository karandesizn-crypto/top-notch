import AppKit
import SwiftUI
import SideNotchCore
import ProviderKit
import UsageKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var manager: UsageManager!
    private var controller: NotchWindowController!
    private var placement: DisplayPlacementService!
    private var notifications: NotificationService!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    nonisolated override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background utility: rail and menu bar only, no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        settings = AppSettings()
        notifications = NotificationService()

        let usingMocks = ProcessInfo.processInfo.environment["SIDENOTCH_MOCK"] == "1"
        // Fixture runs get an in-memory cache. Sharing the real one let a mock render
        // write figures that then outlived it, because a provider whose fetch fails keeps
        // whatever the cache last held.
        let cache: any UsageCaching = usingMocks ? InMemoryUsageCache() : FileUsageCache()

        let providerOverride: [any UsageProvider]? =
            usingMocks ? MockUsageProvider.showcase() : nil

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

        Task {
            await notifications.requestAuthorization()
            await manager.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Terminating the app-server child process matters: it outlives us otherwise.
        let manager = self.manager
        Task { await manager?.stop() }
    }

    // MARK: Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "SideNotch"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SideNotch", action: #selector(quit), keyEquivalent: "q")
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
        window.title = "SideNotch Settings"
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
    }
}
