import Foundation
import OSLog

/// Shared loggers.
///
/// Nothing here may log credentials, tokens, cookies, or account identifiers. Provider
/// responses are logged only as shapes and counts, never as payloads — the Codex reply
/// carries an account-scoped credit id, and the Claude path would carry more.
public enum Log {
    private static let subsystem = "com.hivinz.topnotch"

    public static let provider = Logger(subsystem: subsystem, category: "provider")
    public static let codex = Logger(subsystem: subsystem, category: "codex")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
