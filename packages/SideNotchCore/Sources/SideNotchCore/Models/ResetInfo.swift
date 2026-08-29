import Foundation

/// When a usage window rolls over, and how long that window is.
///
/// `windowDuration` is separate from the reset date because providers report them
/// independently — Codex sends `windowDurationMins` and `resetsAt` as unrelated optional
/// fields, and either can be absent.
public struct ResetInfo: Codable, Sendable, Equatable {
    public let date: Date
    /// Length of the window, when the provider states it.
    public let windowDuration: TimeInterval?

    public init(date: Date, windowDuration: TimeInterval? = nil) {
        self.date = date
        self.windowDuration = windowDuration
    }

    public func timeRemaining(from now: Date = Date()) -> TimeInterval {
        date.timeIntervalSince(now)
    }

    public func hasPassed(at now: Date = Date()) -> Bool {
        timeRemaining(from: now) <= 0
    }
}
