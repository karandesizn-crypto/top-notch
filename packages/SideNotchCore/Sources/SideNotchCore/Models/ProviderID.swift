import Foundation

/// The AI coding tools SideNotch tracks.
public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case chatgpt

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .chatgpt: "ChatGPT"
        }
    }
}
