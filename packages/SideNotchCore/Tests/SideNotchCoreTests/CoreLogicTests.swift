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
        #expect(metrics.anchorTopY == 982)          // merges with the very top of the display
    }

    @Test("a display without a housing falls back to the menu bar")
    func nonNotchedMetrics() {
        let metrics = NotchPlacement.metrics(for: Self.externalDisplay)
        #expect(metrics.hasPhysicalNotch == false)
        #expect(metrics.notchWidth == 0)
        #expect(metrics.notchHeight == 22)
        #expect(metrics.centerX == -1280)           // that display's own centre
        // Hangs below the menu bar rather than covering menu items across the centre.
        #expect(metrics.anchorTopY == 1415)
    }

    @Test("the surface centres on the housing and hangs from the top of the display")
    func surfaceOnNotchedDisplay() {
        let metrics = NotchPlacement.metrics(for: Self.notchedDisplay)
        let frame = NotchPlacement.surfaceFrame(
            size: CGSize(width: 420, height: 38), metrics: metrics, display: Self.notchedDisplay
        )
        #expect(frame.midX == 756)                  // centred on the housing
        #expect(frame.maxY == 982)                  // flush with the top of the display
        #expect(frame.height == 38)
    }

    @Test("expanding grows downward and keeps the top edge pinned")
    func expansionGrowsDownward() {
        let metrics = NotchPlacement.metrics(for: Self.notchedDisplay)
        let collapsed = NotchPlacement.surfaceFrame(
            size: CGSize(width: 420, height: 38), metrics: metrics, display: Self.notchedDisplay
        )
        let expanded = NotchPlacement.surfaceFrame(
            size: CGSize(width: 520, height: 260), metrics: metrics, display: Self.notchedDisplay
        )
        #expect(collapsed.maxY == expanded.maxY)    // the anchor never moves
        #expect(expanded.minY < collapsed.minY)     // it grows down
        #expect(collapsed.midX == expanded.midX)    // and stays centred
    }

    @Test("an external display keeps its own coordinate space")
    func surfaceOnExternalDisplay() {
        let metrics = NotchPlacement.metrics(for: Self.externalDisplay)
        let frame = NotchPlacement.surfaceFrame(
            size: CGSize(width: 420, height: 38), metrics: metrics, display: Self.externalDisplay
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
    /// Built from the measured 185x32 housing.
    let notched = NotchSurfaceLayout(
        notchWidth: 185, notchHeight: 32, flare: 14,
        collapsedFlank: 104, expandedFlank: 150, minimumRowHeight: 26
    )

    /// No housing: both flanks meet in the middle.
    let flat = NotchSurfaceLayout(
        notchWidth: 0, notchHeight: 22, flare: 14,
        collapsedFlank: 104, expandedFlank: 150, minimumRowHeight: 26
    )

    @Test("the collapsed surface straddles the housing")
    func collapsedSize() {
        #expect(notched.collapsedSize.width == 421)    // 185 + 104*2 + 14*2
        #expect(notched.collapsedSize.height == 32)    // the housing's own height
    }

    @Test("expanding grows in both directions")
    func expandedSize() {
        let expanded = notched.expandedSize(rowCount: 2, hasSwitcher: true)
        #expect(expanded.width == 513)                 // 185 + 150*2 + 14*2
        #expect(expanded.width > notched.collapsedSize.width)
        #expect(expanded.height > notched.collapsedSize.height)
    }

    @Test("the body follows its content instead of leaving a void")
    func bodyHeightFollowsContent() {
        // One window and no switcher is the common Codex case; it must not reserve the
        // room a two-window provider with a switcher needs.
        let single = notched.expandedBodyHeight(rowCount: 1, hasSwitcher: false)
        let double = notched.expandedBodyHeight(rowCount: 2, hasSwitcher: false)
        let doubleWithSwitcher = notched.expandedBodyHeight(rowCount: 2, hasSwitcher: true)

        #expect(single < double)
        #expect(double < doubleWithSwitcher)
        #expect(doubleWithSwitcher - double == notched.switcherHeight)
    }

    @Test("the body never shrinks below the usage ring")
    func minimumBodyHeight() {
        #expect(notched.expandedBodyHeight(rowCount: 0, hasSwitcher: false) >= notched.minimumBodyHeight)
        #expect(notched.expandedBodyHeight(rowCount: 1, hasSwitcher: false) >= notched.minimumBodyHeight)
    }

    @Test("a display with no housing still gets a usable row")
    func flatDisplayRow() {
        // A 22pt menu bar is below the floor, so the row uses the minimum instead.
        #expect(flat.rowHeight == 26)
        #expect(flat.collapsedSize.width == 236)       // 0 + 104*2 + 14*2
        #expect(flat.collapsedSize.height == 26)
    }

    @Test("the window is sized for the busiest state, so switching never resizes it")
    func windowSize() {
        #expect(notched.windowSize == notched.maximumExpandedSize)
        // Every reachable state fits inside the window.
        for rows in 0...NotchSurfaceLayout.maximumRows {
            for switcher in [true, false] {
                let size = notched.expandedSize(rowCount: rows, hasSwitcher: switcher)
                #expect(size.height <= notched.windowSize.height)
                #expect(size.width <= notched.windowSize.width)
            }
        }
    }

    @Test("flank width follows the state")
    func flankWidth() {
        #expect(notched.flankWidth(expanded: false) == 104)
        #expect(notched.flankWidth(expanded: true) == 150)
    }

    @Test("layout can be built straight from measured notch metrics")
    func fromMetrics() {
        let metrics = NotchPlacement.metrics(for: NotchPlacementTests.notchedDisplay)
        let layout = NotchSurfaceLayout(
            notch: metrics, flare: 14, collapsedFlank: 104,
            expandedFlank: 150, minimumRowHeight: 26
        )
        #expect(layout == notched)
    }
}
