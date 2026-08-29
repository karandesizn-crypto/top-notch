import Foundation

/// Which limit window a snapshot describes.
public enum UsageScope: String, Codable, Sendable {
    case session
    case weekly
    case monthly
    case model
}
