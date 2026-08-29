import Foundation

/// Locates the Codex executable.
///
/// Codex ships inside the desktop app bundle and can also be installed as a standalone
/// CLI, so both are checked. `PATH` is consulted last and via an explicit list rather than
/// by running a shell, so a user's shell configuration cannot redirect us to an arbitrary
/// binary.
public enum CodexInstallation {
    /// Checked in order; first hit wins.
    static let candidatePaths: [String] = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "\(NSHomeDirectory())/Applications/Codex.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "\(NSHomeDirectory())/.local/bin/codex",
        "\(NSHomeDirectory())/.bun/bin/codex",
    ]

    /// Path to the Codex executable, or nil when Codex is not installed.
    public static func executableURL(fileManager: FileManager = .default) -> URL? {
        for path in candidatePaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public static var isInstalled: Bool { executableURL() != nil }

    /// Codex's home directory. Its presence indicates Codex has been run at least once.
    public static var homeDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    /// Whether Codex has been signed in on this machine.
    ///
    /// Only the *existence* of the auth file is checked. It is never opened, parsed, or
    /// copied — SideNotch has no business reading the user's tokens, and the app-server
    /// handles authentication itself.
    public static func hasStoredAuth(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: homeDirectory.appendingPathComponent("auth.json").path)
    }
}
