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

@Suite("Compact reset phrasing")
struct CompactResetTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("within the hour, minutes")
    func minutes() {
        #expect(ResetCalculator.compactResetPhrase(to: now.addingTimeInterval(51 * 60), from: now)
                == "resets in 51m")
    }

    @Test("within the day, the countdown")
    func sameDay() {
        #expect(ResetCalculator.compactResetPhrase(to: now.addingTimeInterval(5 * 3600), from: now)
                == "resets in 5h 0m")
    }

    @Test("beyond a day, the time of day is dropped")
    func dropsTimeOfDay() throws {
        // "resets Sep 29, 1:38 AM" does not fit in a panel the width of the housing, and
        // the hour is not what someone glancing at a monthly window needs.
        let phrase = try #require(
            ResetCalculator.compactResetPhrase(to: now.addingTimeInterval(30 * 86400), from: now)
        )
        #expect(phrase.hasPrefix("resets "))
        #expect(!phrase.contains(":"))
        #expect(!phrase.contains("AM") && !phrase.contains("PM"))
        #expect(phrase.count <= 16)
    }

    @Test("an elapsed reset says so rather than counting backwards")
    func elapsed() {
        #expect(ResetCalculator.compactResetPhrase(to: now.addingTimeInterval(-60), from: now)
                == "resetting")
    }

    @Test("no reset date yields nothing")
    func noDate() {
        #expect(ResetCalculator.compactResetPhrase(to: nil, from: now) == nil)
    }

    @Test("the compact form is never longer than the full one")
    func alwaysShorter() {
        for days in [0.02, 0.5, 2.0, 30.0] {
            let date = now.addingTimeInterval(days * 86400)
            let full = ResetCalculator.resetPhrase(to: date, from: now) ?? ""
            let compact = ResetCalculator.compactResetPhrase(to: date, from: now) ?? ""
            #expect(compact.count <= full.count)
        }
    }
}

@Suite("Usage state")
struct UsageStateTests {
    let now = Date()

    private func window(_ id: String, _ fraction: Double?) -> UsageWindow {
        UsageWindow(
            id: id, label: id, usedFraction: fraction,
            level: UsageLevelEvaluator.level(forUsedFraction: fraction)
        )
    }

    @Test("the headline is the most constrained window")
    func headline() throws {
        let state = UsageState.live(
            provider: .codex,
            windows: [window("a", 0.2), window("b", 0.91), window("c", 0.5)],
            at: now
        )
        #expect(state.headlineWindow?.id == "b")
        #expect(state.usedPercentage.map { Int($0.rounded()) } == 91)
        #expect(state.remainingPercentage.map { Int($0.rounded()) } == 9)
    }

    @Test("windows without a measurement never become the headline")
    func headlineSkipsUnmeasured() throws {
        let state = UsageState.live(provider: .codex, windows: [window("a", nil), window("b", 0.3)], at: now)
        #expect(state.headlineWindow?.id == "b")
    }

    @Test("level is the worst window's, and only when the provider answered")
    func level() {
        let available = UsageState.live(
            provider: .codex, windows: [window("a", 0.1), window("b", 0.95)], at: now
        )
        #expect(available.level == .critical)

        // An unsupported provider has no level at all — not `.normal`, which would read
        // as "fine".
        #expect(UsageState.unsupported(provider: .claude, reason: "x").level == nil)
        #expect(UsageState.unavailable(provider: .claude, reason: "x").level == nil)
        #expect(UsageState.failed(provider: .claude, reason: "x").level == nil)
        #expect(UsageState.loading(provider: .claude).level == nil)
    }

    @Test("a provider with no windows does not claim to be healthy")
    func noWindows() {
        let state = UsageState.live(provider: .codex, windows: [], at: now)
        #expect(state.level == nil)
        #expect(state.hasFigures == false)
        #expect(state.status == .available)   // an empty answer is still an answer
    }
}

@Suite("LIVE, CACHED, UNSUPPORTED, ERROR")
struct UsageStateSourceTests {
    let now = Date()

    private var liveState: UsageState {
        UsageState.live(
            provider: .codex, plan: "go",
            windows: [UsageWindow.fromPercentage(id: "p", label: "30-day", percent: 40)],
            at: now
        )
    }

    @Test("LIVE carries figures, an available status, and a timestamp")
    func live() {
        let state = liveState
        #expect(state.status == .available)
        #expect(state.source == .live)
        #expect(state.hasFigures)
        #expect(state.lastUpdated == now)
        #expect(state.failure == nil)
    }

    @Test("CACHED keeps the figures but changes the source")
    func cached() {
        // Bound once: the factory mints a fresh id per call.
        let live = liveState
        let cached = live.asCached()
        // Same measurement, different provenance — the distinction the UI needs.
        #expect(cached.source == .cached)
        #expect(cached.status == .available)
        #expect(cached.usedPercentage == live.usedPercentage)
        #expect(cached.lastUpdated == live.lastUpdated)
        #expect(cached.id == live.id)   // identity survives, so it is the same reading
    }

    @Test("caching is idempotent and never promotes a non-live state")
    func cachedIsIdempotent() {
        #expect(liveState.asCached().asCached().source == .cached)
        // Nothing was live to begin with, so nothing is claimed to have been.
        let unsupported = UsageState.unsupported(provider: .claude, reason: "x")
        #expect(unsupported.asCached().source == .unavailable)
    }

    @Test("UNSUPPORTED is structural and carries no figures")
    func unsupported() {
        let state = UsageState.unsupported(provider: .claude, reason: "No local usage API yet")
        #expect(state.status == .unsupported)
        #expect(state.source == .unavailable)
        #expect(state.hasFigures == false)
        #expect(state.failure == "No local usage API yet")
        // Retrying will not help, which is what separates this from `.unavailable`.
        #expect(state.status.isRetryable == false)
    }

    @Test("UNAVAILABLE is transient, and says so")
    func unavailable() {
        let state = UsageState.unavailable(provider: .codex, reason: "Not running")
        #expect(state.status == .unavailable)
        #expect(state.status.isRetryable)
        #expect(state.hasFigures == false)
    }

    @Test("ERROR is distinct from both")
    func error() {
        let state = UsageState.failed(provider: .codex, reason: "Unexpected response")
        #expect(state.status == .error)
        #expect(state.source == .unavailable)
        #expect(state.status.isRetryable)
        #expect(state.hasFigures == false)
    }

    @Test("LOADING is not mistaken for a reading")
    func loading() {
        let state = UsageState.loading(provider: .codex)
        #expect(state.status == .loading)
        #expect(state.lastUpdated == nil)
        #expect(state.hasFigures == false)
    }

    @Test("every status maps to exactly one source expectation")
    func sourceMatchesStatus() {
        // Only a real read is ever `.live`; everything else must not claim to be.
        #expect(liveState.source == .live)
        for state in [
            UsageState.unsupported(provider: .claude, reason: "x"),
            UsageState.unavailable(provider: .claude, reason: "x"),
            UsageState.failed(provider: .claude, reason: "x"),
            UsageState.loading(provider: .claude),
        ] {
            #expect(state.source == .unavailable)
        }
    }

    @Test("states round-trip through Codable with source and status intact")
    func codable() throws {
        for original in [liveState, liveState.asCached(),
                         UsageState.unsupported(provider: .claude, reason: "x")] {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(UsageState.self, from: data)
            #expect(decoded.source == original.source)
            #expect(decoded.status == original.status)
            #expect(decoded.provider == original.provider)
        }
    }
}

@Suite("Staleness")
struct StalenessPolicyTests {
    let policy = StalenessPolicy(maxAge: 900)

    private func aged(_ seconds: TimeInterval, now: Date) -> UsageState {
        UsageState.live(
            provider: .codex,
            windows: [UsageWindow.fromPercentage(id: "p", label: "p", percent: 10)],
            at: now.addingTimeInterval(-seconds)
        )
    }

    @Test("fresh and stale either side of the max age")
    func freshAndStale() {
        let now = Date()
        #expect(policy.isStale(aged(300, now: now), now: now) == false)
        #expect(policy.isStale(aged(1200, now: now), now: now) == true)
    }

    @Test("a cached reading ages exactly as a live one does")
    func cachedAges() {
        // Restoring from disk must not reset the clock, or yesterday's figure looks fresh.
        let now = Date()
        let cached = aged(1200, now: now).asCached()
        #expect(cached.source == .cached)
        #expect(policy.isStale(cached, now: now) == true)
        #expect(policy.age(of: cached, now: now).map { Int($0) } == 1200)
    }

    @Test("a state with no reading is not called stale")
    func neverReadIsNotStale() {
        // "Never read" and "read long ago" are different; only one deserves the mark.
        let now = Date()
        let loading = UsageState.loading(provider: .codex)
        #expect(policy.age(of: loading, now: now) == nil)
        #expect(policy.isStale(loading, now: now) == false)
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
    /// Three tools on the measured housing: 185 x 32pt, read from the display's auxiliary
    /// top areas and safe-area inset rather than hard-coded.
    let three = NotchSurfaceLayout(providerCount: 3, notchWidth: 185, housingRowHeight: 32)

    @Test("the resting panel is exactly the housing's size")
    func matchesTheHousingExactly() {
        // Same width and height, directly beneath it: the notch simply looks twice as tall.
        #expect(three.collapsedSize.width == 185)
        #expect(three.collapsedSize.height == 32)
        #expect(three.collapsedSize.width == three.notchWidth)
        #expect(three.collapsedSize.height == three.housingRowHeight)
    }

    @Test("the panel divides its width between the chips")
    func chipsShareTheWidth() {
        #expect(three.itemCount == 4)               // three rings and the add button
        #expect(three.contentWidth == 169)          // 185 less 8pt padding either side
        #expect(three.chipWidth == 169.0 / 4)
        #expect(three.chipWidth >= three.minimumChipWidth)
        #expect(three.chipRowHeight == 32)
    }

    @Test("enough tools widen the panel rather than squeezing the chips")
    func legibilityWinsEventually() {
        // Six tools plus the add button cannot fit in 185pt at a legible size.
        let many = NotchSurfaceLayout(providerCount: 6, notchWidth: 185, housingRowHeight: 32)
        #expect(many.collapsedSize.width > 185)
        #expect(many.chipWidth >= many.minimumChipWidth)
        // Height still matches the housing; only width gives.
        #expect(many.collapsedSize.height == 32)
    }

    @Test("a housing of another size is followed, not overridden")
    func followsWhateverHousingIsMeasured() {
        // Nothing is hard-coded to this Mac: a different housing produces a different panel.
        let other = NotchSurfaceLayout(providerCount: 3, notchWidth: 220, housingRowHeight: 38)
        #expect(other.collapsedSize == CGSize(width: 220, height: 38))
    }

    @Test("the drawn panel hangs below the camera's row")
    func hangsBelowTheCamera() {
        #expect(three.surfaceTopInset == three.housingRowHeight)
    }

    @Test("minimized leaves a mini-notch, not nothing")
    func minimized() {
        #expect(three.minimizedSize == CGSize(width: 38, height: 5))
        #expect(three.minimizedSize.height < three.collapsedSize.height)
    }

    @Test("hovering adds a snippet, not a panel")
    func snippetIsSmall() {
        #expect(three.expandedBodyHeight(pinned: false) == 52)
        #expect(three.expandedSize(pinned: false).height == three.collapsedSize.height + 52)
    }

    @Test("expanding grows downward only, never wider than the housing")
    func expandingNeverWidens() {
        // A panel wider than the housing has to flare outward from it, and that overhang
        // is what makes the surface look stuck on rather than part of the notch.
        #expect(three.expandedSize(pinned: false).width == three.collapsedSize.width)
        #expect(three.expandedSize(pinned: true).width == three.collapsedSize.width)
        #expect(three.expandedSize(pinned: true).width == three.notchWidth)
    }

    @Test("clicking adds one line, not a panel")
    func pinnedAddsOneLine() {
        let grown = three.expandedBodyHeight(pinned: true)
            - three.expandedBodyHeight(pinned: false)
        #expect(grown == three.pinnedExtraHeight)
    }

    @Test("state selection covers every form")
    func sizeForState() {
        #expect(three.size(expanded: false, minimized: true, pinned: false)
                == three.minimizedSize)
        #expect(three.size(expanded: false, minimized: false, pinned: false)
                == three.collapsedSize)
        #expect(three.size(expanded: true, minimized: false, pinned: true)
                == three.expandedSize(pinned: true))
        // Minimized wins: tucking away must not be undone by a stale hover or pin.
        #expect(three.size(expanded: true, minimized: true, pinned: true)
                == three.minimizedSize)
    }

    @Test("the window fits every reachable state, so changing state never resizes it")
    func windowSize() {
        for count in 1...6 {
            let layout = NotchSurfaceLayout(
                providerCount: count, notchWidth: 185, housingRowHeight: 32
            )
            #expect(layout.windowSize.width >= layout.notchWidth)
            let states = [
                layout.collapsedSize, layout.minimizedSize,
                layout.expandedSize(pinned: false), layout.expandedSize(pinned: true),
            ]
            for size in states {
                #expect(size.width <= layout.windowSize.width)
                #expect(layout.surfaceTopInset + size.height <= layout.windowSize.height)
            }
        }
    }
}

@Suite("Provider identity")
struct ProviderTypeTests {
    @Test("the three built-ins are the shipped set")
    func builtIns() {
        #expect(ProviderType.builtIn == [.claude, .codex, .cursor])
        #expect(ProviderType.claude.isBuiltIn)
        #expect(ProviderType("antigravity").isBuiltIn == false)
    }

    @Test("a custom provider is a first-class identifier")
    func customProvider() {
        let custom = ProviderType("antigravity")
        #expect(custom.rawValue == "antigravity")
        #expect(custom.defaultDisplayName == "Antigravity")
    }

    @Test("identifiers encode as bare strings, so cached snapshots still decode")
    func codingIsStable() throws {
        let data = try JSONEncoder().encode(ProviderType.codex)
        #expect(String(data: data, encoding: .utf8) == "\"codex\"")
        #expect(try JSONDecoder().decode(ProviderType.self, from: data) == .codex)
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
        #expect(ProviderType.slug(from: title) == expected)
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
