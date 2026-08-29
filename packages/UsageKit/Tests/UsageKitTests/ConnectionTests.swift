import Testing
import Foundation
import SideNotchCore
import ProviderKit
@testable import UsageKit

/// Verifies the chain the UI depends on:
/// provider -> UsageState -> UsageManager -> ProviderStatus -> ProviderDisplayState.
///
/// The UI is locked, so these assert the *inputs* it renders from rather than the pixels.
/// Rendered output is covered separately by golden-image comparison.
@MainActor
@Suite("Core reaches the UI")
struct ConnectionTests {

    private final class FixedProvider: UsageProvider, @unchecked Sendable {
        let providerType: ProviderType
        let displayName: String
        private let state: UsageState
        init(_ state: UsageState) {
            self.providerType = state.provider
            self.displayName = state.provider.defaultDisplayName
            self.state = state
        }
        func fetchUsage() async throws -> UsageState { state }
    }

    private func manager(_ states: [UsageState]) -> UsageManager {
        let suite = UserDefaults(suiteName: "ConnectionTests-\(UUID().uuidString)")!
        return UsageManager(
            settings: AppSettings(defaults: suite),
            cache: InMemoryUsageCache(),
            notifications: NotificationService(),
            indicatorHold: .zero,
            providerOverride: states.map(FixedProvider.init)
        )
    }

    private func state(_ provider: ProviderType, percent: Double) -> UsageState {
        UsageState.live(
            provider: provider,
            windows: [UsageWindow.fromPercentage(id: "p", label: "w", percent: percent)]
        )
    }

    @Test(
        "usage levels reach the ring as the matching display state",
        arguments: [
            (10.0, ProviderDisplayState.normal),
            (60.0, .warning),
            (80.0, .critical),
            (100.0, .exhausted),
        ]
    )
    func levelsReachTheRing(percent: Double, expected: ProviderDisplayState) async {
        // Default thresholds are 50/70, so these straddle each boundary.
        let manager = manager([state(.codex, percent: percent)])
        await manager.refresh(.codex)
        #expect(manager.status(for: .codex)?.state == expected)
    }

    @Test("every non-readable status collapses to one inert treatment")
    func nonReadableStatesShareATreatment() async {
        for state in [
            UsageState.unsupported(provider: .codex, reason: "a"),
            UsageState.unavailable(provider: .codex, reason: "b"),
            UsageState.failed(provider: .codex, reason: "c"),
        ] {
            let manager = manager([state])
            await manager.refresh(.codex)
            let status = manager.status(for: .codex)
            // The ring looks the same for all three; the message is what differs, which
            // is exactly what the locked UI already did.
            #expect(status?.state == .unavailable)
            #expect(status?.statusMessage == state.failure)
        }
    }

    @Test("a provider that has never answered reads as loading, not as zero")
    func loadingIsNotZero() {
        let manager = manager([state(.codex, percent: 50)])
        // Before any refresh: no cache, no reading.
        let status = manager.status(for: .codex)
        #expect(status?.state == .loading)
        #expect(status?.headlineWindow == nil)
    }

    @Test("the refresh indicator the ring animates on toggles around a read")
    func refreshIndicatorToggles() async {
        let manager = manager([state(.codex, percent: 20)])
        #expect(manager.status(for: .codex)?.isRefreshing == false)
        await manager.refresh(.codex)
        // Settles back off, so the sweep cannot be left running.
        #expect(manager.status(for: .codex)?.isRefreshing == false)
        #expect(manager.status(for: .codex)?.status == .available)
    }

    @Test("source is visible to the UI without it having to infer anything")
    func sourceIsExposed() async {
        let cache = InMemoryUsageCache()
        cache.save(state(.codex, percent: 30))
        let suite = UserDefaults(suiteName: "ConnectionTests-\(UUID().uuidString)")!
        let manager = UsageManager(
            settings: AppSettings(defaults: suite), cache: cache,
            notifications: NotificationService(), indicatorHold: .zero,
            providerOverride: [FixedProvider(state(.codex, percent: 44))]
        )

        #expect(manager.status(for: .codex)?.source == .cached)
        await manager.refresh(.codex)
        #expect(manager.status(for: .codex)?.source == .live)
    }

    @Test("visible providers follow the enabled set, in a stable order")
    func visibleProvidersAreStable() {
        let manager = manager([
            state(.claude, percent: 1), state(.codex, percent: 2), state(.cursor, percent: 3),
        ])
        // Fixed order matters: chips must not reshuffle under the pointer as readings land.
        #expect(manager.order == [.claude, .codex, .cursor])
        #expect(manager.visibleProviders == manager.order.filter { manager.status(for: $0) != nil })
    }
}

@Suite("Provider registry")
struct ProviderRegistryTests {

    private func context(_ type: ProviderType) -> ProviderRegistry.Context {
        ProviderRegistry.Context(
            providerType: type, displayName: type.defaultDisplayName,
            thresholds: .default, onProviderEvent: {}
        )
    }

    @Test("the shipped registry covers every built-in")
    func standardCoversBuiltIns() {
        let registry = ProviderRegistry.standard
        #expect(Set(registry.registeredTypes) == Set(ProviderType.builtIn))
        for type in ProviderType.builtIn {
            #expect(registry.make(context(type)).providerType == type)
        }
    }

    @Test("an unregistered tool falls back rather than failing")
    func fallbackForCustomTools() {
        // A user-added tool has no adapter; it must still appear, reporting unsupported.
        let provider = ProviderRegistry.standard.make(context(ProviderType("antigravity")))
        #expect(provider.providerType == ProviderType("antigravity"))
    }

    @Test("registering replaces an adapter without touching the manager")
    func registrationOverrides() async throws {
        final class Stub: UsageProvider, @unchecked Sendable {
            let providerType = ProviderType.codex
            let displayName = "Stub"
            func fetchUsage() async throws -> UsageState {
                UsageState.unavailable(provider: .codex, reason: "stubbed")
            }
        }
        var registry = ProviderRegistry.standard
        registry.register(.codex) { _ in Stub() }

        // This is the extensibility claim: swapping an integration is a registration.
        let state = try await registry.make(context(.codex)).fetchUsage()
        #expect(state.failure == "stubbed")
    }
}
