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

@Suite("Rail geometry")
struct RailGeometryTests {
    // Matches the shipping tokens: 74pt rail, 78pt slots, three providers.
    let geometry = RailGeometry(
        verticalPadding: 14, itemHeight: 78, ringTopInset: 8, ringDiameter: 42, itemCount: 3
    )

    @Test("panel height covers every slot plus padding")
    func panelHeight() {
        // 14pt padding top and bottom, three 78pt slots.
        #expect(geometry.panelHeight == 262)
    }

    @Test(
        "ring centres step by one slot height",
        arguments: [(0, CGFloat(43)), (1, 121), (2, 199)]
    )
    func ringCentres(index: Int, expected: CGFloat) {
        #expect(geometry.ringCenterY(index: index) == expected)
    }

    @Test("a tall card centres on its ring")
    func tallCardCentres() {
        // Ring 1 sits at 121; a 120pt card centred on it starts at 61.
        #expect(geometry.cardOffset(index: 1, cardHeight: 120) == 61)
        #expect(geometry.tailCenterY(index: 1, cardHeight: 120) == 60)
    }

    @Test("a card taller than its ring offset clamps to the panel top")
    func clampsToTop() {
        #expect(geometry.cardOffset(index: 0, cardHeight: 150) == 0)
        // Tail still points at the ring, which is inside the card.
        #expect(geometry.tailCenterY(index: 0, cardHeight: 150) == 43)
    }

    @Test("a card near the bottom clamps inside the panel")
    func clampsToBottom() {
        let height: CGFloat = 100
        let offset = geometry.cardOffset(index: 2, cardHeight: height)
        #expect(offset + height <= geometry.panelHeight)
        // The tail must still land on the ring rather than being pushed off the card.
        let tail = geometry.tailCenterY(index: 2, cardHeight: height)
        #expect(tail >= 0 && tail <= height)
    }

    @Test("zero card height is inert rather than producing a negative offset")
    func zeroHeight() {
        #expect(geometry.cardOffset(index: 2, cardHeight: 0) == 0)
    }
}
