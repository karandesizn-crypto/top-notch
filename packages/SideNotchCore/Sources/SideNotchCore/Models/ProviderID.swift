import Foundation

/// The AI coding tools SideNotch tracks.
public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claude
    case cursor
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .codex: "Codex"
        }
    }
}
