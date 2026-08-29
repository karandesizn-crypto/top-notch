import Testing
import Foundation
@testable import SideNotchCore

@Suite("Reset countdown")
struct ResetCalculatorTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("no reset date yields no countdown")
    func noDate() {
        #expect(ResetCalculator.countdown(to: nil as Date?, from: now) == nil)
        #expect(ResetCalculator.resetPhrase(to: nil, from: now) == nil)
    }

    @Test("hours and minutes")
    func hoursAndMinutes() {
        let reset = now.addingTimeInterval(2 * 3600 + 14 * 60)
        #expect(ResetCalculator.countdown(to: reset, from: now) == "2h 14m")
        #expect(ResetCalculator.resetPhrase(to: reset, from: now) == "Resets in 2h 14m")
    }

    @Test("under an hour reads in minutes, matching the product copy")
    func minutesPhrase() {
        let reset = now.addingTimeInterval(51 * 60)
        #expect(ResetCalculator.countdown(to: reset, from: now) == "51m")
        #expect(ResetCalculator.resetPhrase(to: reset, from: now) == "Resets in 51 min")
    }

    @Test("multi-day resets name the day rather than counting hours")
    func namesTheDay() throws {
        let reset = now.addingTimeInterval(3 * 86400)
        let phrase = try #require(ResetCalculator.resetPhrase(to: reset, from: now))
        #expect(phrase.hasPrefix("Resets "))
        #expect(!phrase.contains("in "))     // "Resets Sunday 8:00 PM", not "Resets in 3d"
        #expect(ResetCalculator.countdown(to: reset, from: now) == "3d 0h")
    }

    @Test("sub-minute rounds up rather than showing 0m")
    func subMinute() {
        #expect(ResetCalculator.countdown(to: now.addingTimeInterval(20), from: now) == "1m")
    }

    @Test("an elapsed reset reads as resetting, never as a negative countdown")
    func elapsed() {
        #expect(ResetCalculator.countdown(to: now.addingTimeInterval(-60), from: now) == "now")
        #expect(ResetCalculator.resetPhrase(to: now.addingTimeInterval(-60), from: now) == "Resetting now")
    }

    // Durations in seconds, precomputed: the compiler cannot type-check arithmetic
    // inside a parameterized `arguments` array in reasonable time.
    static let labelCases: [(TimeInterval, String)] = [
        (18_000, "5-hour"),      // 300 min
        (604_800, "Weekly"),     // 10080 min
        (86_400, "Daily"),       // 1440 min
        (2_592_000, "30-day"),   // 43200 min
        (5_400, "90-minute"),
    ]

    @Test("window labels derive from duration", arguments: ResetCalculatorTests.labelCases)
    func windowLabels(duration: TimeInterval, expected: String) {
        #expect(ResetCalculator.windowLabel(forDuration: duration) == expected)
    }

    @Test("no duration yields no label rather than an invented one")
    func noDuration() {
        #expect(ResetCalculator.windowLabel(forDuration: nil) == nil)
        #expect(ResetCalculator.windowLabel(forDuration: 0) == nil)
    }
}

@Suite("Snapshot behaviour")
struct SnapshotTests {
    let now = Date()

    private func snapshot(_ fractions: [Double?]) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            windows: fractions.enumerated().map { index, fraction in
                UsageWindow(
                    id: "w\(index)", label: "w\(index)", usedFraction: fraction,
                    state: UsageStateEvaluator.state(forUsedFraction: fraction)
                )
            },
            lastUpdated: now
        )
    }

    @Test("the headline is the most constrained window")
    func headline() throws {
        let headline = try #require(snapshot([0.2, 0.91, 0.5]).headlineWindow)
        #expect(headline.id == "w1")
    }

    @Test("windows without a measurement do not become the headline")
    func headlineSkipsUnmeasured() throws {
        let headline = try #require(snapshot([nil, 0.3]).headlineWindow)
        #expect(headline.id == "w1")
    }

    @Test("overall state is the worst window's state")
    func overallState() {
        #expect(snapshot([0.1, 0.85]).overallState == .warning)
        #expect(snapshot([0.1, 0.95]).overallState == .critical)
        #expect(snapshot([1.0, 0.1]).overallState == .exhausted)
    }

    @Test("an unavailable snapshot reports unavailable regardless of stale windows")
    func unavailableSnapshot() {
        let snapshot = UsageSnapshot.unavailable(provider: .cursor, reason: "no local data")
        #expect(snapshot.overallState == .unavailable)
        #expect(snapshot.availability.reason == "no local data")
        #expect(snapshot.headlineWindow == nil)
    }

    @Test("a provider with no windows does not claim to be healthy")
    func noWindows() {
        #expect(snapshot([]).overallState == .unavailable)
    }

    @Test("remaining fraction complements used fraction")
    func remaining() {
        let window = UsageWindow.fromPercentage(id: "p", label: "l", percent: 73)
        #expect(abs((window.remainingFraction ?? 0) - 0.27) < 0.0001)
        #expect(abs((window.usedPercentage ?? 0) - 73) < 0.0001)
    }

    @Test("a window with no measurement has no remaining fraction either")
    func noMeasurement() {
        let window = UsageWindow.fromPercentage(id: "p", label: "l", percent: nil)
        #expect(window.usedFraction == nil)
        #expect(window.remainingFraction == nil)
        #expect(window.state == .unavailable)
    }
}

@Suite("Staleness")
struct StalenessPolicyTests {
    @Test("fresh and stale either side of the max age")
    func freshAndStale() {
        let now = Date()
        let policy = StalenessPolicy(maxAge: 900)
        func snapshot(ageSeconds: TimeInterval) -> UsageSnapshot {
            UsageSnapshot(provider: .codex, lastUpdated: now.addingTimeInterval(-ageSeconds))
        }
        #expect(policy.isStale(snapshot(ageSeconds: 300), now: now) == false)
        #expect(policy.isStale(snapshot(ageSeconds: 1200), now: now) == true)
    }
}

@Suite("Rail geometry")
struct RailGeometryTests {
    let geometry = RailGeometry(
        verticalPadding: 14, itemHeight: 78, ringTopInset: 8, ringDiameter: 42, itemCount: 3
    )

    @Test("panel height covers every slot plus padding")
    func panelHeight() {
        // 14pt padding top and bottom, three 78pt slots.
        #expect(geometry.panelHeight == 262)
    }

    static let ringCases: [(Int, CGFloat)] = [(0, 43), (1, 121), (2, 199)]

    @Test("ring centres step by one slot height", arguments: RailGeometryTests.ringCases)
    func ringCentres(index: Int, expected: CGFloat) {
        #expect(geometry.ringCenterY(index: index) == expected)
    }

    @Test("a tall card centres on its ring")
    func tallCardCentres() {
        #expect(geometry.cardOffset(index: 1, cardHeight: 120) == 61)
        #expect(geometry.tailCenterY(index: 1, cardHeight: 120) == 60)
    }

    @Test("a card taller than its ring offset clamps to the panel top")
    func clampsToTop() {
        #expect(geometry.cardOffset(index: 0, cardHeight: 150) == 0)
        #expect(geometry.tailCenterY(index: 0, cardHeight: 150) == 43)
    }

    @Test("a card near the bottom stays inside the panel with its tail on the ring")
    func clampsToBottom() {
        let height: CGFloat = 100
        let offset = geometry.cardOffset(index: 2, cardHeight: height)
        #expect(offset + height <= geometry.panelHeight)
        let tail = geometry.tailCenterY(index: 2, cardHeight: height)
        #expect(tail >= 0 && tail <= height)
    }

    @Test("zero card height is inert rather than producing a negative offset")
    func zeroHeight() {
        #expect(geometry.cardOffset(index: 2, cardHeight: 0) == 0)
    }
}

@Suite("Rail placement")
struct RailPlacementTests {
    let panel = CGSize(width: 348, height: 262)

    @Test("the rail hugs the right edge, below the menu bar")
    func builtInDisplay() {
        // A 1512x982 built-in display with a 37pt menu bar.
        let frame = RailPlacement.frame(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
            panelSize: panel, topInset: 8
        )
        #expect(frame.maxX == 1512)             // flush right
        #expect(frame.maxY == 937)              // 8pt below the menu bar
        #expect(frame.size == panel)
    }

    @Test("an external display to the left keeps its own coordinates")
    func negativeOriginDisplay() {
        // Secondary monitors sit at negative origins when placed left of the built-in.
        let frame = RailPlacement.frame(
            screenFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1415),
            panelSize: panel, topInset: 8
        )
        #expect(frame.maxX == 0)                // right edge of that display
        #expect(frame.minX == -348)
        #expect(frame.maxY == 1407)
    }

    @Test("a Dock at the bottom does not move the rail, which anchors to the top")
    func dockDoesNotMatter() {
        let withoutDock = RailPlacement.frame(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
            panelSize: panel, topInset: 8
        )
        let withDock = RailPlacement.frame(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 80, width: 1512, height: 865),
            panelSize: panel, topInset: 8
        )
        #expect(withoutDock == withDock)
    }

    @Test("a display shorter than the rail keeps the top of the rail on screen")
    func veryShortDisplay() {
        let frame = RailPlacement.frame(
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 180),
            panelSize: panel, topInset: 8
        )
        #expect(frame.minY >= 0)
    }

    @Test("notch detection keys off the safe area")
    func notchDetection() {
        #expect(RailPlacement.hasNotch(safeAreaTopInset: 32) == true)
        #expect(RailPlacement.hasNotch(safeAreaTopInset: 0) == false)
    }
}

@Suite("Card clamping in a taller panel")
struct CardContainerTests {
    // One provider: a short rail inside a panel kept tall enough for a full card.
    let geometry = RailGeometry(
        verticalPadding: 14, itemHeight: 78, ringTopInset: 8, ringDiameter: 42, itemCount: 1
    )

    @Test("a card taller than the rail is not clipped to the rail's height")
    func cardTallerThanRail() {
        #expect(geometry.panelHeight == 106)
        let cardHeight: CGFloat = 220

        // Clamped to the rail, the card would be forced to offset 0 and overflow.
        let clampedToRail = geometry.cardOffset(index: 0, cardHeight: cardHeight)
        #expect(clampedToRail + cardHeight > geometry.panelHeight)

        // Clamped to the panel, it fits.
        let clampedToPanel = geometry.cardOffset(
            index: 0, cardHeight: cardHeight, containerHeight: 320
        )
        #expect(clampedToPanel + cardHeight <= 320)
    }

    @Test("the tail still lands on the ring inside the taller panel")
    func tailStillOnRing() {
        let tail = geometry.tailCenterY(index: 0, cardHeight: 220, containerHeight: 320)
        #expect(tail == geometry.ringCenterY(index: 0))   // card sits at offset 0
        #expect(tail >= 0 && tail <= 220)
    }
}
