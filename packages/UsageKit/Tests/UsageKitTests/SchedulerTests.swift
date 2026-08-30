import Testing
import Foundation
@testable import UsageKit

@MainActor
@Suite("Refresh scheduler")
struct RefreshSchedulerTests {

    /// Records what the scheduler asked for, so timing policy can be tested without
    /// touching a provider.
    private final class Recorder {
        var triggers: [RefreshTrigger] = []
        var ticks = 0
        /// Held open to keep a refresh "in flight" while a second is attempted.
        var gate: CheckedContinuation<Void, Never>?
    }

    @Test("starting performs a launch refresh")
    func launchRefresh() async {
        let recorder = Recorder()
        let scheduler = RefreshScheduler(
            interval: { 3600 },
            tick: { recorder.ticks += 1 },
            perform: { recorder.triggers.append($0) }
        )
        scheduler.start()
        // Yield until the launch refresh has run.
        for _ in 0..<20 where recorder.triggers.isEmpty { await Task.yield() }
        scheduler.stop()

        #expect(recorder.triggers == [.launch])
    }

    @Test("a refresh in flight blocks a second from starting")
    func coalescesWhileInFlight() async {
        let recorder = Recorder()
        let scheduler = RefreshScheduler(
            interval: { 3600 },
            tick: {},
            perform: { trigger in
                recorder.triggers.append(trigger)
                // Hold the first one open, so the second arrives while it is running.
                if recorder.triggers.count == 1 {
                    await withCheckedContinuation { recorder.gate = $0 }
                }
            }
        )

        let first = Task { await scheduler.request(.manual) }
        for _ in 0..<50 where recorder.gate == nil { await Task.yield() }

        // Arrives mid-flight, and must be dropped rather than queued: a burst of triggers
        // should not become a burst of reads. Hover can fire this dozens of times.
        await scheduler.request(.expansion)
        #expect(recorder.triggers == [.manual])

        recorder.gate?.resume()
        await first.value

        // Once the first finishes, a later request is accepted again.
        await scheduler.request(.periodic)
        #expect(recorder.triggers == [.manual, .periodic])
    }

    @Test("a click during a refresh runs afterwards instead of vanishing")
    func userRequestSurvivesCoalescing() async {
        // The exception to dropping. Nobody notices a discarded hover; everybody notices
        // pressing refresh and watching nothing happen.
        let recorder = Recorder()
        let scheduler = RefreshScheduler(
            interval: { 3600 },
            tick: {},
            perform: { trigger in
                recorder.triggers.append(trigger)
                if recorder.triggers.count == 1 {
                    await withCheckedContinuation { recorder.gate = $0 }
                }
            }
        )

        let first = Task { await scheduler.request(.periodic) }
        for _ in 0..<50 where recorder.gate == nil { await Task.yield() }

        await scheduler.request(.manual)
        // Not run yet — the first is still in flight.
        #expect(recorder.triggers == [.periodic])

        recorder.gate?.resume()
        await first.value

        #expect(recorder.triggers == [.periodic, .manual])
    }

    @Test("only one follow-up is held, however many clicks arrive")
    func atMostOneFollowUp() async {
        let recorder = Recorder()
        let scheduler = RefreshScheduler(
            interval: { 3600 },
            tick: {},
            perform: { trigger in
                recorder.triggers.append(trigger)
                if recorder.triggers.count == 1 {
                    await withCheckedContinuation { recorder.gate = $0 }
                }
            }
        )

        let first = Task { await scheduler.request(.periodic) }
        for _ in 0..<50 where recorder.gate == nil { await Task.yield() }

        // Five impatient clicks must not become five reads.
        for _ in 0..<5 { await scheduler.request(.manual) }
        recorder.gate?.resume()
        await first.value

        #expect(recorder.triggers == [.periodic, .manual])
    }

    @Test("a refresh is due by the wall clock, not by time spent sleeping")
    func overdueIsDecidedByWallClock() async {
        // The lid-open case. `Task.sleep` does not advance while the system is asleep, so
        // a loop that trusts elapsed sleep would show hours-old figures and wait a full
        // interval before correcting itself. Here the clock jumps forward while the sleep
        // returns immediately — which is exactly what waking from sleep looks like.
        let recorder = Recorder()
        var clock = Date(timeIntervalSince1970: 1_788_000_000)

        let scheduler = RefreshScheduler(
            interval: { 300 },
            tick: { recorder.ticks += 1 },
            perform: { recorder.triggers.append($0) },
            now: { clock },
            sleep: { _ in
                // Stand in for the machine being asleep: no real time passes here, but
                // the wall clock has moved on a long way.
                await Task.yield()
            }
        )

        scheduler.start()
        for _ in 0..<50 where recorder.triggers.isEmpty { await Task.yield() }
        #expect(recorder.triggers == [.launch])

        // Eight hours pass with the lid shut.
        clock = clock.addingTimeInterval(8 * 3600)
        for _ in 0..<200 where recorder.triggers.count < 2 { await Task.yield() }
        scheduler.stop()

        #expect(recorder.triggers.count >= 2)
        #expect(recorder.triggers[1] == .periodic)
    }

    @Test("the loop does not refresh before the interval has actually elapsed")
    func notOverdueEarly() async {
        let recorder = Recorder()
        var clock = Date(timeIntervalSince1970: 1_788_000_000)

        let scheduler = RefreshScheduler(
            interval: { 300 },
            tick: { recorder.ticks += 1 },
            perform: { recorder.triggers.append($0) },
            now: { clock },
            sleep: { _ in await Task.yield() }
        )

        scheduler.start()
        for _ in 0..<50 where recorder.triggers.isEmpty { await Task.yield() }

        // Well short of the interval: the loop spins, ticks, and must not read again.
        clock = clock.addingTimeInterval(30)
        for _ in 0..<200 { await Task.yield() }
        scheduler.stop()

        #expect(recorder.triggers == [.launch])
        // But countdowns still re-render, which is the other job of the loop.
        #expect(recorder.ticks > 0)
    }

    @Test("a clock that jumps backwards triggers a refresh rather than a long wait")
    func backwardsClockRefreshes() async {
        let recorder = Recorder()
        var clock = Date(timeIntervalSince1970: 1_788_000_000)

        let scheduler = RefreshScheduler(
            interval: { 300 },
            tick: {},
            perform: { recorder.triggers.append($0) },
            now: { clock },
            sleep: { _ in await Task.yield() }
        )

        scheduler.start()
        for _ in 0..<50 where recorder.triggers.isEmpty { await Task.yield() }

        // A timezone or NTP correction. Waiting out an interval measured against a clock
        // that just moved backwards could stall the app for an unbounded time.
        clock = clock.addingTimeInterval(-3600)
        for _ in 0..<200 where recorder.triggers.count < 2 { await Task.yield() }
        scheduler.stop()

        #expect(recorder.triggers.count >= 2)
    }

    @Test("stopping prevents further periodic work")
    func stopHalts() async {
        let recorder = Recorder()
        let scheduler = RefreshScheduler(
            interval: { 0.05 },
            tick: { recorder.ticks += 1 },
            perform: { recorder.triggers.append($0) }
        )
        scheduler.start()
        for _ in 0..<20 where recorder.triggers.isEmpty { await Task.yield() }
        scheduler.stop()

        let afterStop = recorder.triggers.count
        try? await Task.sleep(for: .milliseconds(200))
        // No periodic tick should land after stop, or a quit would leave work running.
        #expect(recorder.triggers.count == afterStop)
    }

    @Test("starting twice does not double the schedule")
    func startIsIdempotent() async {
        let recorder = Recorder()
        let scheduler = RefreshScheduler(
            interval: { 3600 }, tick: {}, perform: { recorder.triggers.append($0) }
        )
        scheduler.start()
        scheduler.start()
        for _ in 0..<20 where recorder.triggers.isEmpty { await Task.yield() }
        scheduler.stop()

        #expect(recorder.triggers == [.launch])
    }

    @Test("the interval is read each cycle, so a settings change takes effect")
    func intervalIsReadLive() async {
        // Reading the interval per cycle rather than capturing it at start is what lets a
        // preference change apply without restarting the loop.
        var current: TimeInterval = 3600
        var reads = 0
        let scheduler = RefreshScheduler(
            interval: { reads += 1; return current },
            tick: {}, perform: { _ in }
        )
        scheduler.start()
        for _ in 0..<40 where reads == 0 { await Task.yield() }
        current = 1
        scheduler.stop()

        #expect(reads >= 1)
    }
}
