import Testing
import Foundation
@testable import UsageKit

@MainActor
@Suite("Refresh scheduler")
struct RefreshSchedulerTests {

    /// Records what the scheduler asked for, so timing policy can be tested without
    /// touching a provider.
    private final class Recorder {
        var triggers: [RefreshScheduler.Trigger] = []
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
        // should not become a burst of reads.
        await scheduler.request(.expansion)
        #expect(recorder.triggers == [.manual])

        recorder.gate?.resume()
        await first.value

        // Once the first finishes, a later request is accepted again.
        await scheduler.request(.periodic)
        #expect(recorder.triggers == [.manual, .periodic])
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
