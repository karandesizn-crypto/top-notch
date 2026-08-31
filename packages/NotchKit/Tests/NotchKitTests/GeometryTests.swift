import Testing
import Foundation
@testable import NotchKit

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

    @Test("a hairline overflow snaps to the notch instead of showing as ears")
    func hairlineFlareSnaps() {
        // Five items need 186pt against a 185pt notch. Drawn literally, the panel overhangs
        // the physical notch by half a point per side, and the shoulder curve spreads that
        // over a ten-point drop into a visible ear at each lower corner.
        let five = NotchSurfaceLayout(
            providerCount: 4, notchWidth: 185, showsAddButton: true,
            minimumChipWidth: 34, horizontalPadding: 8
        )
        #expect(five.collapsedSize.width == 185)
    }

    @Test("a flare wide enough to read as deliberate is kept")
    func realFlareSurvives() {
        // Legibility still wins once the chips genuinely need the room: this is the case
        // the snap must not swallow.
        let many = NotchSurfaceLayout(
            providerCount: 7, notchWidth: 185, showsAddButton: true,
            minimumChipWidth: 34, horizontalPadding: 8
        )
        // Eight items at 34pt plus 16pt of padding. Compared with a tolerance rather than
        // `==`: the macro reports both sides as 288.0 and the equality as false, which is
        // the same inline-arithmetic trap this suite has hit before.
        let difference = abs(many.collapsedSize.width - 288)
        #expect(difference < 0.0001)
        #expect(many.collapsedSize.width > 185)
    }

    @Test("the panel never ends up narrower than the housing")
    func neverNarrowerThanNotch() {
        let few = NotchSurfaceLayout(
            providerCount: 1, notchWidth: 185, showsAddButton: false,
            minimumChipWidth: 34, horizontalPadding: 8
        )
        #expect(few.collapsedSize.width == 185)
    }

    @Test("clicking grows the panel by a title plus one row per limit")
    func pinnedGrowsByRow() {
        let hover = three.expandedBodyHeight(pinned: false)

        // A provider with no measurable window still gets its title line, and nothing more.
        #expect(three.expandedBodyHeight(pinned: true, rows: 0) - hover == three.pinnedTitleHeight)

        // Each additional limit adds exactly one row, so two limits are visibly taller than
        // one — which is the whole reason the breakdown exists.
        let one = three.expandedBodyHeight(pinned: true, rows: 1)
        let two = three.expandedBodyHeight(pinned: true, rows: 2)
        #expect(two - one == three.pinnedRowHeight)
        #expect(one - hover == three.pinnedTitleHeight + three.pinnedRowHeight)
    }

    @Test("the breakdown is bounded, so one provider cannot grow the panel without limit")
    func pinnedRowsAreCapped() {
        let capped = three.expandedBodyHeight(pinned: true, rows: NotchSurfaceLayout.maximumPinnedRows)
        let beyond = three.expandedBodyHeight(pinned: true, rows: 99)
        #expect(beyond == capped)
    }

    @Test("the window is sized for the tallest breakdown, so pinning never resizes it")
    func windowFitsTheTallestState() {
        // Expanding has to be a pure SwiftUI animation. If the window had to grow when the
        // panel did, the growth would lag the content by a frame and read as a stutter.
        let tallest = three.surfaceTopInset
            + three.expandedSize(pinned: true, rows: NotchSurfaceLayout.maximumPinnedRows).height
        #expect(three.windowSize.height >= tallest)
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
