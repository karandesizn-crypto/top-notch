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
public final class NotificationService {
    public init() {}

    /// Highest state already announced for each window, keyed provider + window.
    private var announced: [String: UsageLevel] = [:]
    private var isAuthorized = false

    public static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    public func requestAuthorization() async {
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
    /// Notifies on escalation into warning, critical, or exhausted.
    ///
    /// Only ever called with an `.available` state, so a provider that cannot be read
    /// never produces an alert — and a window with no measurement cannot escalate.
    public func evaluate(_ usage: UsageState, displayName: String, enabled: Bool) {
        guard enabled, isAuthorized, Self.isAvailable, usage.status == .available else { return }

        for window in usage.windows {
            guard let level = window.level else { continue }
            let key = "\(usage.provider.rawValue).\(window.id)"
            let previous = announced[key] ?? .normal

            guard level.severity > previous.severity,
                  level == .warning || level == .critical || level == .exhausted
            else {
                // Recovery re-arms the alert for the next cycle.
                if level.severity < previous.severity { announced[key] = level }
                continue
            }

            announced[key] = level
            post(for: window, provider: displayName, level: level)
        }
    }

    private func post(for window: UsageWindow, provider: String, level: UsageLevel) {
        let content = UNMutableNotificationContent()
        let percentage = window.usedPercentage.map { "\(Int($0.rounded()))%" } ?? "—"

        switch level {
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
    public func reset() { announced.removeAll() }
}
