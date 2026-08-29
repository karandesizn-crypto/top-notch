import Foundation
import SideNotchCore

/// A JSON-RPC client for `codex app-server`, spoken over the child process's stdio.
///
/// The app-server is Codex's own supported integration surface — the same one its editor
/// extensions use — so SideNotch never touches `~/.codex/auth.json`, never handles OAuth
/// tokens, and never calls a provider web endpoint directly. Authentication is entirely
/// the app-server's business.
///
/// One long-lived process is kept for the app's lifetime rather than spawned per refresh:
/// launching Codex costs far more than a request, and a persistent connection is what
/// makes `account/rateLimits/updated` notifications possible.
actor CodexAppServerClient {
    /// JSON-RPC method names, verified against the schema emitted by the installed binary.
    enum Method {
        static let initialize = "initialize"
        static let initialized = "initialized"
        static let readRateLimits = "account/rateLimits/read"
        static let readTokenUsage = "account/usage/read"
        static let rateLimitsUpdated = "account/rateLimits/updated"
    }

    private struct Envelope: Decodable {
        let id: Int?
        let method: String?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let code: Int
        let message: String
    }

    private struct ResultWrapper<T: Decodable>: Decodable {
        let result: T
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextRequestID = 1
    private var isReady = false

    /// Called on every server notification. Set before `start()`.
    private var notificationHandler: (@Sendable (String) async -> Void)?

    private let clientName: String
    private let clientVersion: String
    private let requestTimeout: TimeInterval

    init(clientName: String = "SideNotch", clientVersion: String = "1.0.0", requestTimeout: TimeInterval = 15) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.requestTimeout = requestTimeout
    }

    func setNotificationHandler(_ handler: @escaping @Sendable (String) async -> Void) {
        notificationHandler = handler
    }

    var isRunning: Bool { isReady && process?.isRunning == true }

    // MARK: Lifecycle

    /// Launches the app-server and completes the handshake. Idempotent.
    func start() async throws {
        if isRunning { return }
        stopWithoutClearingHandler()

        guard let executable = CodexInstallation.executableURL() else {
            throw ProviderError.notInstalled
        }

        let inPipe = Pipe()
        let outPipe = Pipe()

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = inPipe
        process.standardOutput = outPipe
        // stderr is discarded rather than piped: an undrained pipe eventually blocks the
        // child, and its contents are diagnostics we must not log anyway.
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        do {
            try process.run()
        } catch {
            Log.codex.error("app-server failed to launch")
            throw ProviderError.notRunning
        }

        self.process = process
        self.stdinHandle = inPipe.fileHandleForWriting
        startReadLoop(on: outPipe.fileHandleForReading)
        isReady = true

        do {
            _ = try await request(
                Method.initialize,
                params: [
                    "clientInfo": [
                        "name": clientName,
                        "version": clientVersion,
                    ]
                ],
                as: JSONIgnored.self
            )
            try writeNotification(Method.initialized)
            Log.codex.info("app-server ready")
        } catch {
            stopWithoutClearingHandler()
            throw error
        }
    }

    func stop() {
        notificationHandler = nil
        stopWithoutClearingHandler()
    }

    private func stopWithoutClearingHandler() {
        isReady = false
        readTask?.cancel()
        readTask = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        failAllPending(with: ProviderError.notRunning)
    }

    // MARK: Requests

    /// Sends a request and waits for its response.
    func request<T: Decodable & Sendable>(
        _ method: String,
        params: [String: Any]? = nil,
        as type: T.Type
    ) async throws -> T {
        guard isReady, process?.isRunning == true else { throw ProviderError.notRunning }

        let id = nextRequestID
        nextRequestID += 1

        var payload: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { payload["params"] = params }
        try write(payload)

        // Registering the continuation happens with no suspension after the write, so the
        // read loop — which needs this actor — cannot deliver a response before the
        // continuation exists.
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.requestTimeout ?? 15))
            await self?.failPending(id: id, with: ProviderError.network(detail: "request timed out"))
        }
        defer { timeoutTask.cancel() }

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
        }

        do {
            return try JSONDecoder().decode(ResultWrapper<T>.self, from: data).result
        } catch {
            throw ProviderError.invalidResponse(detail: "could not decode \(method) result")
        }
    }

    private func write(_ payload: [String: Any]) throws {
        guard let stdinHandle else { throw ProviderError.notRunning }
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw ProviderError.unknown(detail: "could not encode request")
        }
        data.append(0x0A)
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw ProviderError.notRunning
        }
    }

    private func writeNotification(_ method: String) throws {
        try write(["jsonrpc": "2.0", "method": method])
    }

    // MARK: Reading

    private func startReadLoop(on handle: FileHandle) {
        readTask = Task { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    if Task.isCancelled { return }
                    await self?.handle(line: line)
                }
            } catch {
                // Falls through to disconnect handling below.
            }
            await self?.handleDisconnect()
        }
    }

    private func handle(line: String) async {
        let data = Data(line.utf8)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return  // Not a JSON-RPC frame; the app-server may emit other output.
        }

        if let id = envelope.id, let continuation = pending.removeValue(forKey: id) {
            if let error = envelope.error {
                continuation.resume(throwing: Self.providerError(forRPCCode: error.code, message: error.message))
            } else {
                continuation.resume(returning: data)
            }
            return
        }

        if let method = envelope.method, envelope.id == nil {
            await notificationHandler?(method)
        }
    }

    private func handleDisconnect() {
        guard isReady else { return }
        Log.codex.notice("app-server connection closed")
        isReady = false
        failAllPending(with: ProviderError.notRunning)
    }

    private func failPending(id: Int, with error: ProviderError) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failAllPending(with error: ProviderError) {
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting { continuation.resume(throwing: error) }
    }

    /// Maps a JSON-RPC error onto a provider error.
    ///
    /// The message is inspected only for auth wording; it is never logged, because a
    /// server error string can quote request content.
    static func providerError(forRPCCode code: Int, message: String) -> ProviderError {
        let lowered = message.lowercased()
        if lowered.contains("unauthor") || lowered.contains("not logged in")
            || lowered.contains("login") || lowered.contains("sign in") {
            return .authenticationRequired
        }
        // JSON-RPC reserves -32601 for an unknown method: the interface has moved.
        if code == -32601 {
            return .unsupported(reason: "Codex no longer exposes this method")
        }
        return .invalidResponse(detail: "app-server error \(code)")
    }
}

/// Placeholder for responses whose body we do not read, such as `initialize`.
struct JSONIgnored: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}
