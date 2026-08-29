import Foundation

/// Identifies a provider.
///
/// A string wrapper rather than an enum, so a user can add a tool SideNotch has never heard
/// of — Antigravity, an internal gateway, whatever — without a code change. Built-ins are
/// static constants, which keeps `.codex` reading exactly as it did when this was an enum.
public struct ProviderID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var id: String { rawValue }

    // MARK: Built-ins

    public static let claude = ProviderID("claude")
    public static let codex = ProviderID("codex")
    public static let cursor = ProviderID("cursor")

    /// The three providers that ship with an adapter, in presentation order.
    public static let builtIn: [ProviderID] = [.claude, .codex, .cursor]

    public var isBuiltIn: Bool { Self.builtIn.contains(self) }

    /// Fallback name for a provider with no configured title.
    public var defaultDisplayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        default: rawValue.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    // MARK: Codable

    /// Encoded as a bare string, so a snapshot cached when this was an enum still decodes.
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Normalizes user input into an identifier: lowercased, spaces to hyphens.
    public static func slug(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let hyphenated = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return String(hyphenated.unicodeScalars.filter { allowed.contains($0) })
    }
}
