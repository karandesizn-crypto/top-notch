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

    /// Windows are built with explicit states so these assertions test "worst wins"
    /// rather than whatever the default thresholds happen to be.
    private func snapshot(states windows: [(Double?, UsageState)]) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            windows: windows.enumerated().map { index, entry in
                UsageWindow(
                    id: "w\(index)", label: "w\(index)",
                    usedFraction: entry.0, state: entry.1
                )
            },
            lastUpdated: now
        )
    }

    private func snapshot(_ fractions: [Double?]) -> UsageSnapshot {
        snapshot(states: fractions.map { ($0, UsageStateEvaluator.state(forUsedFraction: $0)) })
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
        #expect(snapshot(states: [(0.1, .normal), (0.6, .warning)]).overallState == .warning)
        #expect(snapshot(states: [(0.1, .normal), (0.8, .critical)]).overallState == .critical)
        #expect(snapshot(states: [(1.0, .exhausted), (0.1, .normal)]).overallState == .exhausted)
        // An unavailable window never outranks a real measurement.
        #expect(snapshot(states: [(nil, .unavailable), (0.6, .warning)]).overallState == .warning)
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

@Suite("Notch placement")
struct NotchPlacementTests {
    /// A 14" MacBook Pro, measured from AppKit rather than assumed: 1512x982 with a 32pt
    /// safe area and 663.5pt auxiliary areas either side of a 185pt housing.
    static let notchedDisplay = DisplayMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 663.5,
        auxiliaryTopRightWidth: 663.5,
        menuBarHeight: 22,
        backingScaleFactor: 2
    )

    /// An external monitor: no housing, no safe area.
    static let externalDisplay = DisplayMetrics(
        frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: 0, width: 2560, height: 1415),
        safeAreaTop: 0,
        auxiliaryTopLeftWidth: nil,
        auxiliaryTopRightWidth: nil,
        menuBarHeight: 22,
        backingScaleFactor: 1
    )

    @Test("a physical notch is measured, not assumed")
    func notchedMetrics() {
        let metrics = NotchPlacement.metrics(for: Self.notchedDisplay)
        #expect(metrics.hasPhysicalNotch)
        #expect(metrics.notchWidth == 185)
        #expect(metrics.notchHeight == 32)          // safe area, not the 22pt menu bar
        #expect(metrics.centerX == 756)
        #expect(metrics.notchMinX == 663.5)
        #expect(metrics.notchMaxX == 848.5)
        // The surface occupies the notch row itself, so it anchors to the very top.
        #expect(metrics.anchorTopY == 982)
    }

    @Test("a display without a housing hangs below the menu bar")
    func nonNotchedMetrics() {
        let metrics = NotchPlacement.metrics(for: Self.externalDisplay)
        #expect(metrics.hasPhysicalNotch == false)
        #expect(metrics.notchWidth == 0)
        #expect(metrics.notchHeight == 22)
        #expect(metrics.centerX == -1280)           // that display's own centre
        #expect(metrics.anchorTopY == 1415)
    }

    @Test("the surface centres on the housing and fills the notch row")
    func surfaceOnNotchedDisplay() {
        let metrics = NotchPlacement.metrics(for: Self.notchedDisplay)
        let frame = NotchPlacement.surfaceFrame(
            size: CGSize(width: 340, height: 32), metrics: metrics, display: Self.notchedDisplay
        )
        #expect(frame.midX == 756)                  // centred on the housing
        #expect(frame.maxY == 982)                  // flush with the top of the display
        // Exactly the housing's height, so it sits inside the notch row.
        #expect(frame.minY == 950)
    }

    @Test("expanding grows downward and keeps the top edge pinned")
    func expansionGrowsDownward() {
        let metrics = NotchPlacement.metrics(for: Self.notchedDisplay)
        let collapsed = NotchPlacement.surfaceFrame(
            size: CGSize(width: 340, height: 32), metrics: metrics, display: Self.notchedDisplay
        )
        let expanded = NotchPlacement.surfaceFrame(
            size: CGSize(width: 340, height: 200), metrics: metrics, display: Self.notchedDisplay
        )
        #expect(collapsed.maxY == expanded.maxY)    // the anchor never moves
        #expect(expanded.minY < collapsed.minY)     // it grows down
        #expect(collapsed.midX == expanded.midX)    // and stays centred
    }

    @Test("an external display keeps its own coordinate space")
    func surfaceOnExternalDisplay() {
        let metrics = NotchPlacement.metrics(for: Self.externalDisplay)
        let frame = NotchPlacement.surfaceFrame(
            size: CGSize(width: 220, height: 30), metrics: metrics, display: Self.externalDisplay
        )
        #expect(frame.midX == -1280)
        #expect(frame.maxY == 1415)                 // below that display's menu bar
        #expect(frame.minX < 0)                     // negative origin is preserved
    }

    @Test("a surface wider than the display is clamped on screen")
    func clampsOversizedSurface() {
        let metrics = NotchPlacement.metrics(for: Self.notchedDisplay)
        let frame = NotchPlacement.surfaceFrame(
            size: CGSize(width: 4000, height: 60), metrics: metrics, display: Self.notchedDisplay
        )
        #expect(frame.minX == 0)
    }

    @Test("a display reporting only one auxiliary area is treated as un-notched")
    func partialAuxiliaryAreas() {
        // Defensive: mixed reporting during a display reconfiguration must not produce a
        // negative notch width.
        let display = DisplayMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            safeAreaTop: 32, auxiliaryTopLeftWidth: 663.5, auxiliaryTopRightWidth: nil,
            menuBarHeight: 22, backingScaleFactor: 2
        )
        let metrics = NotchPlacement.metrics(for: display)
        #expect(metrics.hasPhysicalNotch == false)
        #expect(metrics.notchWidth == 0)
    }

    @Test("lengths align to whole pixels at the display's scale")
    func pixelAlignment() {
        #expect(NotchPlacement.pixelAligned(10.3, scale: 2) == 10.5)
        #expect(NotchPlacement.pixelAligned(10.3, scale: 1) == 10)
        #expect(NotchPlacement.pixelAligned(10.26, scale: 3).isFinite)
    }
}

@Suite("Notch surface layout")
struct NotchSurfaceLayoutTests {
    /// Three tools on the measured 185x32 housing.
    let three = NotchSurfaceLayout(providerCount: 3, notchWidth: 185, notchHeight: 32)

    /// A display with no housing: the flanks meet in the middle.
    let flat = NotchSurfaceLayout(providerCount: 3, notchWidth: 0, notchHeight: 22)

    @Test("the collapsed row spans the housing with chips either side")
    func collapsedSpansHousing() {
        // Four items -- three rings and the add button -- split two and two.
        #expect(three.itemWidths.count == 4)
        #expect(three.leadingItemCount == 2)
        #expect(three.leadingFlankWidth == 60)       // two 30pt rings
        #expect(three.trailingFlankWidth == 56)      // one ring plus the 26pt add button

        // 185 housing + 60 + 56 + 22 padding + 20 flare.
        #expect(three.collapsedSize.width == 343)
    }

    @Test("the collapsed row is exactly the height of the housing")
    func collapsedFillsNotchRow() {
        // Sitting inside the notch means matching its height, not the tab's own default.
        #expect(three.collapsedSize.height == 32)
    }

    @Test("an odd number of items puts the extra one on the left")
    func oddSplit() {
        let two = NotchSurfaceLayout(providerCount: 2, notchWidth: 185, notchHeight: 32)
        #expect(two.itemWidths.count == 3)           // two rings and the add button
        #expect(two.leadingItemCount == 2)
        #expect(two.trailingFlankWidth == 26)        // just the add button
    }

    @Test("hiding the add button reclaims its width")
    func addButtonWidth() {
        let without = NotchSurfaceLayout(
            providerCount: 3, notchWidth: 185, notchHeight: 32, showsAddButton: false
        )
        #expect(three.collapsedSize.width - without.collapsedSize.width == 26)
        #expect(without.itemWidths.count == 3)
    }

    @Test("a display with no housing loses the gap entirely")
    func flatDisplay() {
        #expect(flat.collapsedSize.width == three.collapsedSize.width - 185)
        // Still tall enough to be legible where the menu bar is shorter than the tab.
        #expect(flat.collapsedSize.height == 30)
    }

    @Test("expanding grows downward from the same top edge")
    func expandedSize() {
        let expanded = three.expandedSize(rowCount: 2)
        #expect(expanded.height > three.collapsedSize.height)
        #expect(expanded.height == three.collapsedHeight + three.expandedBodyHeight(rowCount: 2))
        // Never narrower than the collapsed row, so expanding cannot pinch the surface in.
        #expect(expanded.width >= three.collapsedSize.width)
    }

    @Test("the body follows its content instead of opening onto empty space")
    func bodyHeightFollowsContent() {
        let single = three.expandedBodyHeight(rowCount: 1)
        let double = three.expandedBodyHeight(rowCount: 2)
        #expect(single < double)
        #expect(double - single == three.contentRowHeight + three.contentRowSpacing)
    }

    @Test("a provider with no windows still gets one row's worth of space")
    func zeroRows() {
        #expect(three.expandedBodyHeight(rowCount: 0) == three.expandedBodyHeight(rowCount: 1))
    }

    @Test("the window fits every reachable state, so expanding never resizes it")
    func windowSize() {
        for count in 1...6 {
            let layout = NotchSurfaceLayout(
                providerCount: count, notchWidth: 185, notchHeight: 32
            )
            #expect(layout.windowSize.width >= layout.collapsedSize.width)
            for rows in 0...NotchSurfaceLayout.maximumRows {
                let size = layout.expandedSize(rowCount: rows)
                #expect(size.width <= layout.windowSize.width)
                #expect(size.height <= layout.windowSize.height)
            }
        }
    }

    @Test("many providers widen the row past the expanded panel")
    func manyProviders() {
        let many = NotchSurfaceLayout(
            providerCount: 6, notchWidth: 185, notchHeight: 32, chipWidth: 58
        )
        #expect(many.collapsedSize.width > 322)
        #expect(many.windowSize.width == many.collapsedSize.width)
    }
}

@Suite("Provider identity")
struct ProviderIDTests {
    @Test("the three built-ins are the shipped set")
    func builtIns() {
        #expect(ProviderID.builtIn == [.claude, .codex, .cursor])
        #expect(ProviderID.claude.isBuiltIn)
        #expect(ProviderID("antigravity").isBuiltIn == false)
    }

    @Test("a custom provider is a first-class identifier")
    func customProvider() {
        let custom = ProviderID("antigravity")
        #expect(custom.rawValue == "antigravity")
        #expect(custom.defaultDisplayName == "Antigravity")
    }

    @Test("identifiers encode as bare strings, so cached snapshots still decode")
    func codingIsStable() throws {
        let data = try JSONEncoder().encode(ProviderID.codex)
        #expect(String(data: data, encoding: .utf8) == "\"codex\"")
        #expect(try JSONDecoder().decode(ProviderID.self, from: data) == .codex)
    }

    @Test(
        "titles become usable identifiers",
        arguments: [
            ("Antigravity", "antigravity"),
            ("My Gateway", "my-gateway"),
            ("  Spaced  ", "spaced"),
            ("Weird!!Chars", "weirdchars"),
        ]
    )
    func slugs(title: String, expected: String) {
        #expect(ProviderID.slug(from: title) == expected)
    }
}

@Suite("Choosing a display")
struct PreferredDisplayTests {
    let notched = NotchPlacementTests.notchedDisplay
    let external = NotchPlacementTests.externalDisplay

    @Test("the notched display wins even when an external one has focus")
    func prefersNotchedOverFocused() {
        // Working on the external monitor must not drag the surface off the notch.
        let index = NotchPlacement.preferredDisplayIndex(
            among: [notched, external], mainIndex: 1, allowingDisplaysWithoutNotch: false
        )
        #expect(index == 0)
    }

    @Test("a lone external display hides the surface by default")
    func hidesWithoutNotch() {
        // Nothing to attach to: it would float over whatever window is at the top edge.
        #expect(NotchPlacement.preferredDisplayIndex(
            among: [external], mainIndex: 0, allowingDisplaysWithoutNotch: false
        ) == nil)
    }

    @Test("Macs with no notch at all can opt in")
    func optInWithoutNotch() {
        // Without this escape hatch those users would never see the surface.
        #expect(NotchPlacement.preferredDisplayIndex(
            among: [external], mainIndex: 0, allowingDisplaysWithoutNotch: true
        ) == 0)
    }

    @Test("opting in still prefers a notched display when one is attached")
    func optInStillPrefersNotch() {
        #expect(NotchPlacement.preferredDisplayIndex(
            among: [external, notched], mainIndex: 0, allowingDisplaysWithoutNotch: true
        ) == 1)
    }

    @Test("no displays yields nothing rather than a crash")
    func noDisplays() {
        #expect(NotchPlacement.preferredDisplayIndex(
            among: [], mainIndex: nil, allowingDisplaysWithoutNotch: true
        ) == nil)
    }

    @Test("an out-of-range focused index falls back to the first display")
    func staleMainIndex() {
        // A display can be unplugged between the index being read and being used.
        #expect(NotchPlacement.preferredDisplayIndex(
            among: [external], mainIndex: 7, allowingDisplaysWithoutNotch: true
        ) == 0)
    }
}
