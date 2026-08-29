import Foundation

/// Turns a reset date into the countdown string the rail and detail card show.
public enum ResetCalculator {
    /// Compact countdown, e.g. "2h 14m", "48m", "3d 4h".
    ///
    /// Returns nil when there is no reset date. Returns "now" once the reset has passed —
    /// the next poll will carry the new window.
    public static func countdown(to resetAt: Date?, from now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return "now" }

        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    /// Full phrasing for the detail card, e.g. "resets in 2h 14m".
    public static func resetPhrase(to resetAt: Date?, from now: Date = Date()) -> String? {
        guard let value = countdown(to: resetAt, from: now) else { return nil }
        return value == "now" ? "resetting now" : "resets in \(value)"
    }
}
