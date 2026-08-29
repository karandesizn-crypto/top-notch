import AppKit

// An accessory app with a borderless panel is clearer to drive from AppKit directly than
// through the SwiftUI App lifecycle, which wants to own window creation.
//
// Top-level code is nonisolated but does run on the main thread before the run loop
// starts, so assuming main-actor isolation here is sound. The delegate is held in a global
// because NSApplication does not retain it.
private let appDelegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.delegate = appDelegate
    application.run()
}
