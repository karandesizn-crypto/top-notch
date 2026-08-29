import Testing
import Foundation
@testable import SideNotchCore

@Suite("Health evaluation")
struct HealthEvaluatorTests {
    @Test("unknown percentage is unavailable, never healthy")
    func unknownIsUnavailable() {
        #expect(HealthEvaluator.health(forPercentageUsed: nil) == .unavailable)
    }

    @Test(
        "threshold boundaries",
        arguments: [
            (0.0, UsageHealth.healthy),
            (79.9, .healthy),
            (80.0, .warning),
            (89.9, .warning),
            (90.0, .critical),
            (99.9, .critical),
            (100.0, .exhausted),
            (140.0, .exhausted),
        ]
    )
    func boundaries(percentage: Double, expected: UsageHealth) {
        #expect(HealthEvaluator.health(forPercentageUsed: percentage) == expected)
    }

    @Test("custom thresholds are respected")
    func customThresholds() {
        let thresholds = UsageThresholds(warning: 50, critical: 70)
        #expect(HealthEvaluator.health(forPercentageUsed: 55, thresholds: thresholds) == .warning)
        #expect(HealthEvaluator.health(forPercentageUsed: 45, thresholds: thresholds) == .healthy)
    }
}

@Suite("Reset countdown")
struct ResetCalculatorTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("no reset date yields no countdown")
    func noDate() {
        #expect(ResetCalculator.countdown(to: nil, from: now) == nil)
    }

    @Test("hours and minutes")
    func hoursAndMinutes() {
        let reset = now.addingTimeInterval(2 * 3600 + 14 * 60)
        #expect(ResetCalculator.countdown(to: reset, from: now) == "2h 14m")
        #expect(ResetCalculator.resetPhrase(to: reset, from: now) == "resets in 2h 14m")
    }

    @Test("minutes only")
    func minutesOnly() {
        #expect(ResetCalculator.countdown(to: now.addingTimeInterval(48 * 60), from: now) == "48m")
    }

    @Test("days for long windows")
    func days() {
        let reset = now.addingTimeInterval(3 * 86400 + 4 * 3600)
        #expect(ResetCalculator.countdown(to: reset, from: now) == "3d 4h")
    }

    @Test("sub-minute rounds up rather than showing 0m")
    func subMinute() {
        #expect(ResetCalculator.countdown(to: now.addingTimeInterval(20), from: now) == "1m")
    }

    @Test("elapsed reset reads as now")
    func elapsed() {
        #expect(ResetCalculator.countdown(to: now.addingTimeInterval(-60), from: now) == "now")
    }
}

@Suite("Staleness")
struct StalenessPolicyTests {
    @Test("fresh and stale either side of the max age")
    func freshAndStale() {
        let now = Date()
        let policy = StalenessPolicy(maxAge: 900)
        func snapshot(ageSeconds: TimeInterval) -> UsageSnapshot {
            UsageSnapshot(
                provider: .codex, percentageUsed: 10, scope: .monthly, health: .healthy,
                observedAt: now.addingTimeInterval(-ageSeconds), source: .localApp
            )
        }
        #expect(policy.isStale(snapshot(ageSeconds: 300), now: now) == false)
        #expect(policy.isStale(snapshot(ageSeconds: 1200), now: now) == true)
    }
}
