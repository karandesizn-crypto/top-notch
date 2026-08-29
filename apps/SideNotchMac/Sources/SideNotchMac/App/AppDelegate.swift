import AppKit
import SideNotchCore
import ProviderKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: RailWindowController?
    private var store: UsageStore?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Utility app: rail and menu bar only, no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        let store = UsageStore(providers: Self.configuredProviders())
        let controller = RailWindowController(store: store)
        self.store = store
        self.controller = controller

        // Offscreen render mode for design verification; see PreviewRenderer.
        if let path = ProcessInfo.processInfo.environment["SIDENOTCH_RENDER"] {
            Task {
                await store.refresh()
                let focused = ProcessInfo.processInfo.environment["SIDENOTCH_RENDER_FOCUS"]
                    .flatMap(ProviderID.init(rawValue:))
                PreviewRenderer.render(to: path, store: store, focused: focused)
                NSApp.terminate(nil)
            }
            return
        }

        store.start()
        controller.show()
        installStatusItem()

        if ProcessInfo.processInfo.environment["SIDENOTCH_DIAGNOSE"] == "1" {
            print(controller.placementDescription())
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }

    /// `SIDENOTCH_MOCK=1` swaps in fixture data — the design system is meant to be worked
    /// on without waiting for a real limit to move.
    private static func configuredProviders() -> [any UsageProvider] {
        if ProcessInfo.processInfo.environment["SIDENOTCH_MOCK"] == "1" {
            return MockProvider.showcase()
        }
        return [ClaudeProvider(), CodexProvider(), CursorProvider()]
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "SideNotch"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit SideNotch", action: #selector(quit), keyEquivalent: "q"
        ).target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func refreshNow() {
        Task { await store?.refresh() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
