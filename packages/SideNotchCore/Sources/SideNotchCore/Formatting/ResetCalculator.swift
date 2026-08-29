import Foundation

/// Turns a reset date into the countdown text the rail and card show.
public enum ResetCalculator {
    /// Compact countdown: "2h 14m", "48m", "3d 4h".
    ///
    /// Nil when there is no reset date. "now" once the reset has passed — the next refresh
    /// carries the new window.
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

    public static func countdown(to reset: ResetInfo?, from now: Date = Date()) -> String? {
        countdown(to: reset?.date, from: now)
    }

    /// Phrasing for the detail card: "Resets in 51 min" within a day, otherwise a weekday
    /// and time — "6d 3h" is less useful to a person than "Resets Sunday 8:00 PM".
    public static func resetPhrase(
        to resetAt: Date?, from now: Date = Date(), calendar: Calendar = .current
    ) -> String? {
        guard let resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return "Resetting now" }

        if remaining < 3600 {
            return "Resets in \(max(Int(remaining / 60), 1)) min"
        }
        if remaining < 86400 {
            guard let value = countdown(to: resetAt, from: now) else { return nil }
            return "Resets in \(value)"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = remaining < 7 * 86400 ? "EEEE h:mm a" : "MMM d, h:mm a"
        return "Resets \(formatter.string(from: resetAt))"
    }

    /// A reset phrase short enough for a panel the width of the camera housing.
    ///
    /// Drops the time of day beyond a day out: "resets Sep 29, 1:38 AM" does not fit in
    /// 185pt beside a percentage, and the hour is not what someone glancing at a monthly
    /// window needs. Within a day the countdown is the useful part, so it stays.
    public static func compactResetPhrase(
        to resetAt: Date?, from now: Date = Date(), calendar: Calendar = .current
    ) -> String? {
        guard let resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return "resetting" }

        if remaining < 3600 {
            return "resets in \(max(Int(remaining / 60), 1))m"
        }
        if remaining < 86400 {
            guard let value = countdown(to: resetAt, from: now) else { return nil }
            return "resets in \(value)"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(remaining < 7 * 86400 ? "EEE" : "MMMd")
        return "resets \(formatter.string(from: resetAt))"
    }

    /// Human label for a window duration, e.g. "5-hour", "Weekly", "30-day".
    public static func windowLabel(forDuration duration: TimeInterval?) -> String? {
        guard let duration, duration > 0 else { return nil }
        let minutes = Int(duration / 60)
        if minutes % (60 * 24) == 0 {
            let days = minutes / (60 * 24)
            if days == 7 { return "Weekly" }
            if days == 1 { return "Daily" }
            return "\(days)-day"
        }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-minute"
    }
}
