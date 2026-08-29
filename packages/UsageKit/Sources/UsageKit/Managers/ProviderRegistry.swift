import Foundation
import SideNotchCore
import ProviderKit

/// Builds provider adapters on demand.
///
/// The manager used to construct its providers inline, which meant every new integration
/// edited the same function and the manager had to know each adapter's initializer. A
/// registry inverts that: an adapter registers itself and the manager only asks for one by
/// type. Adding a provider becomes a registration, and tests can substitute the whole set
/// without touching production code.
public struct ProviderRegistry: Sendable {
    /// What an adapter may need at construction. Passed in rather than reached for, so a
    /// provider never captures the manager.
    public struct Context: Sendable {
        public let providerType: ProviderType
        public let displayName: String
        public let thresholds: UsageThresholds
        /// Called when a provider pushes an update of its own, so the manager can re-read
        /// without waiting for the schedule.
        public let onProviderEvent: @Sendable () async -> Void

        public init(
            providerType: ProviderType,
            displayName: String,
            thresholds: UsageThresholds,
            onProviderEvent: @escaping @Sendable () async -> Void
        ) {
            self.providerType = providerType
            self.displayName = displayName
            self.thresholds = thresholds
            self.onProviderEvent = onProviderEvent
        }
    }

    public typealias Factory = @Sendable (Context) -> any UsageProvider

    private var factories: [ProviderType: Factory]
    /// Used for any type with no registered factory — a tool the user added by hand.
    private let fallback: Factory

    public init(
        factories: [ProviderType: Factory] = [:],
        fallback: @escaping Factory = { context in
            CustomUsageProvider(
                providerType: context.providerType, displayName: context.displayName
            )
        }
    ) {
        self.factories = factories
        self.fallback = fallback
    }

    /// The providers that ship with the app.
    ///
    /// Claude and Cursor are registered even though neither can be read yet: their
    /// adapters report `.unsupported`, which is a state the UI shows deliberately. Leaving
    /// them out would make them silently absent instead.
    public static var standard: ProviderRegistry {
        ProviderRegistry(factories: [
            .claude: { _ in ClaudeUsageProvider() },
            .codex: { context in
                CodexUsageProvider(thresholds: context.thresholds) {
                    await context.onProviderEvent()
                }
            },
            .cursor: { _ in CursorUsageProvider() },
        ])
    }

    public mutating func register(_ providerType: ProviderType, factory: @escaping Factory) {
        factories[providerType] = factory
    }

    public func make(_ context: Context) -> any UsageProvider {
        (factories[context.providerType] ?? fallback)(context)
    }

    public var registeredTypes: [ProviderType] {
        ProviderType.builtIn.filter { factories[$0] != nil }
    }
}
