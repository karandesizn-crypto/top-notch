import Foundation
import SideNotchCore

/// ChatGPT adapter — not implemented.
///
/// ChatGPT plan usage is account state held by OpenAI; the desktop app ships no local
/// interface that reports it, and there is no supported CLI equivalent of Codex's
/// app-server to ask.
///
/// Worth noting that Codex usage is already metered against the same ChatGPT plan — the
/// `planType` in a Codex snapshot is the user's ChatGPT plan. So on a machine with Codex
/// installed, the Codex provider is the closest available answer to "how much of my
/// ChatGPT plan is left", and this adapter exists for the day a distinct interface appears.
///
/// The only alternative route is `chatgpt.com/backend-api/wham/usage` with the user's
/// session credentials, which the project rules exclude.
public struct ChatGPTUsageProvider: UsageProvider {
    public let id: ProviderID = .chatgpt
    public let displayName = "ChatGPT"

    public init() {}

    public func fetchSnapshot() async throws -> UsageSnapshot {
        throw ProviderError.unsupported(
            reason: "ChatGPT exposes no local usage interface; Codex reports the same plan"
        )
    }
}
