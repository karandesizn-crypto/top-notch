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

@Suite("Reset term, for columns")
struct ResetTermTests {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    @Test("the term carries no leading verb")
    func noVerb() {
        // The column heading already says these are resets. Repeating "resets in" on every
        // row is what made the 185pt panel truncate mid-word.
        let soon = ResetCalculator.resetTerm(to: now.addingTimeInterval(7_260), from: now)
        #expect(soon == "2h 1m")
        #expect(soon?.contains("resets") == false)
    }

    @Test("beyond a day it names the day rather than counting hours")
    func namesTheDay() {
        let term = ResetCalculator.resetTerm(to: now.addingTimeInterval(3 * 86_400), from: now)
        let phrase = ResetCalculator.compactResetPhrase(to: now.addingTimeInterval(3 * 86_400), from: now)
        // Same day, stated without the verb the phrase form uses.
        #expect(term != nil)
        #expect(phrase?.hasSuffix(term ?? "|") == true)
    }

    @Test("an elapsed reset says now, and no reset says nothing")
    func edges() {
        #expect(ResetCalculator.resetTerm(to: now.addingTimeInterval(-60), from: now) == "now")
        #expect(ResetCalculator.resetTerm(to: nil, from: now) == nil)
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

