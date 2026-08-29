import Foundation
import ServiceManagement
import ProviderKit

/// Login-item registration.
///
/// `SMAppService.mainApp` requires a real app bundle with a bundle identifier; a bare
/// executable run via `swift run` cannot register. Rather than failing loudly, this reports
/// itself unsupported so the settings UI can explain why the toggle does nothing.
enum LaunchAtLogin {
    static var isSupported: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        guard isSupported else {
            Log.app.notice("launch at login unavailable: not running from a bundle")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("could not update login item")
        }
    }
}
