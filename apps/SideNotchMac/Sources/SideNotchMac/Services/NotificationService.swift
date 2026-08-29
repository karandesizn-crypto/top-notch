import Foundation
import UserNotifications
import ProviderKit
import SideNotchCore

/// Threshold alerts.
///
/// Two rules keep this from becoming noise:
///
/// 1. One notification per window per state escalation. Crossing 80% notifies once; staying
///    above 80% does not notify again. Dropping back below re-arms it, which is what
///    happens naturally when a window resets.
/// 2. Nothing fires unless the app is bundled and the user has granted permission.
///    `UNUserNotificationCenter` requires a bundle identifier and traps without one, so a
///    plain `swift run` must not reach it.
@MainActor
final class NotificationService {
    /// Highest state already announced for each window, keyed provider + window.
    private var announced: [String: UsageState] = [:]
    private var isAuthorized = false

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() async {
        guard Self.isAvailable else {
            Log.app.notice("notifications unavailable: app is not running from a bundle")
            return
        }
        do {
            isAuthorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.app.notice("notification authorization declined")
            isAuthorized = false
        }
    }

    /// Notifies on escalation into warning, critical, or exhausted.
    func evaluate(_ snapshot: UsageSnapshot, displayName: String, enabled: Bool) {
        guard enabled, isAuthorized, Self.isAvailable else { return }

        for window in snapshot.windows {
            let key = "\(snapshot.provider.rawValue).\(window.id)"
            let previous = announced[key] ?? .normal

            guard window.state.severity > previous.severity,
                  window.state == .warning || window.state == .critical || window.state == .exhausted
            else {
                // Recovery re-arms the alert for the next cycle.
                if window.state.severity < previous.severity { announced[key] = window.state }
                continue
            }

            announced[key] = window.state
            post(for: window, provider: displayName, state: window.state)
        }
    }

    private func post(for window: UsageWindow, provider: String, state: UsageState) {
        let content = UNMutableNotificationContent()
        let percentage = window.usedPercentage.map { "\(Int($0.rounded()))%" } ?? "—"

        switch state {
        case .exhausted:
            content.title = "\(provider) limit reached"
            content.body = "\(window.label) is exhausted."
        case .critical:
            content.title = "\(provider) nearly exhausted"
            content.body = "\(window.label) is \(percentage) used."
        default:
            content.title = "\(provider) usage high"
            content.body = "\(window.label) is \(percentage) used."
        }

        if let phrase = ResetCalculator.resetPhrase(to: window.resetDate) {
            content.body += " \(phrase)."
        }
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    /// Clears announcement state, e.g. when the user changes thresholds.
    func reset() { announced.removeAll() }
}
