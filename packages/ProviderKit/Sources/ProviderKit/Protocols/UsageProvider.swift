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
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }

    /// Prepares long-lived resources. Must be safe to call more than once.
    func start() async

    /// Releases those resources. Must be safe to call without a prior `start()`.
    func stop() async

    /// Reads current usage. Throws `ProviderError`; never blocks indefinitely.
    func fetchSnapshot() async throws -> UsageSnapshot
}

public extension UsageProvider {
    func start() async {}
    func stop() async {}
}
