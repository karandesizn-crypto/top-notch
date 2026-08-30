import Foundation
import SideNotchCore

/// A provider the user added themselves.
///
/// Top Notch cannot invent an integration for a tool it has never heard of, so this reports
/// `.unsupported` and says so plainly. It exists because the alternative — refusing to show
/// the tool at all — is worse: a user who works across four assistants wants all four in the
/// row, even if only some report numbers.
///
/// When a tool does ship a supported local interface, writing an adapter for it is the only
/// change needed; nothing above `UsageProvider` knows the difference.
public struct CustomUsageProvider: UsageProvider {
    public let providerType: ProviderType
    public let displayName: String

    public init(providerType: ProviderType, displayName: String) {
        self.providerType = providerType
        self.displayName = displayName
    }

    public func fetchUsage() async throws -> UsageState {
        UsageState.unsupported(provider: providerType, reason: "No usage interface")
    }
}
