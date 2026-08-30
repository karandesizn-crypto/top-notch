import Foundation
import SideNotchCore

/// Everything that can go wrong reading a provider.
///
/// Distinguishing these is what lets the UI say something useful: "Codex isn't installed"
/// and "Codex needs you to sign in" are both unavailable, but only one is worth a button.
public enum ProviderError: Error, Equatable, Sendable {
    /// The provider's software is not present on this machine.
    case notInstalled
    /// Present, but its local interface could not be started or has stopped.
    case notRunning
    /// Reachable, but the user is not signed in.
    case authenticationRequired
    /// This provider has no supported way to report usage yet.
    case unsupported(reason: String)
    case network(detail: String)
    /// Reached the provider, but could not make sense of the reply — usually an
    /// interface change.
    case invalidResponse(detail: String)
    case unknown(detail: String)

    /// Short phrasing for the UI. Must never include credentials or raw responses.
    ///
    /// Terse on purpose: this is rendered in a snippet the width of the camera housing —
    /// 185pt — where anything longer truncates mid-word. The full reasoning for each
    /// unsupported provider lives in its adapter's documentation, not in the string.
    public var userFacingDescription: String {
        switch self {
        case .notInstalled: "Not installed"
        case .notRunning: "Not running"
        case .authenticationRequired: "Sign-in required"
        case .unsupported(let reason): reason
        case .network: "Network unavailable"
        case .invalidResponse: "Unexpected response"
        case .unknown: "Unavailable"
        }
    }
}

/// The boundary between the app and however a provider's usage is obtained.
///
/// Deliberately free of any UI type. Adapters may spawn processes, read files, or call
/// services; nothing above this protocol knows which.
public extension String {
    /// Clamps a string to something the rail can actually render.
    ///
    /// The transport failure path is the one place a `detail` string reaches
    /// `UsageState.failure`, which the surface draws in a strip the width of the camera
    /// housing. Today those details come from a fixed internal vocabulary — "Offline",
    /// "Timed out" — so the clamp never fires. It exists because that is a property of the
    /// current implementation rather than of the type: widening the vocabulary to include
    /// `localizedDescription`, which is locale-dependent and can run to a paragraph, would
    /// otherwise silently start rendering it.
    var railSafe: String {
        let limit = 32
        guard count > limit else { return self }
        return String(prefix(limit - 1)) + "…"
    }
}

public protocol UsageProvider: Sendable {
    var providerType: ProviderType { get }
    var displayName: String { get }

    /// Prepares long-lived resources. Must be safe to call more than once.
    func startMonitoring() async

    /// Releases those resources. Must be safe to call without a prior `startMonitoring()`.
    func stopMonitoring() async

    /// Reads current usage.
    ///
    /// Returns a `UsageState` carrying its own status and source, rather than throwing for
    /// "no data available" — an unsupported provider is a legitimate answer, not a failure.
    /// Throwing is reserved for genuine read errors, which the manager turns into an
    /// `.unavailable` or `.error` state.
    func fetchUsage() async throws -> UsageState
}

public extension UsageProvider {
    func startMonitoring() async {}
    func stopMonitoring() async {}
}

public extension ProviderError {
    /// The status a failed read should be recorded as.
    ///
    /// `.unsupported` is structural — the provider has no readable interface — so it is
    /// kept distinct from failures that a later attempt might survive.
    var status: UsageStatus {
        switch self {
        case .unsupported: .unsupported
        case .notInstalled, .notRunning, .authenticationRequired, .network: .unavailable
        case .invalidResponse, .unknown: .error
        }
    }
}
