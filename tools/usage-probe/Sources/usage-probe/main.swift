import Foundation
import SideNotchCore
import ProviderKit

// Verifies each adapter end to end against whatever is actually installed.

let providers: [any UsageProvider] = [
    CodexUsageProvider(),
    ClaudeUsageProvider(),
    CursorUsageProvider(),
]

let staleness = StalenessPolicy.default
let now = Date()

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

print("")
print("Codex installed: \(CodexInstallation.isInstalled)   signed in: \(CodexInstallation.hasStoredAuth())")
if let url = CodexInstallation.executableURL() { print("Executable:      \(url.path)") }
print("")

let columns = [("PROVIDER", 10), ("WINDOW", 18), ("USED", 8), ("RESETS", 24), ("STATE", 13)]
print(columns.map { pad($0.0, $0.1) }.joined())
print(String(repeating: "─", count: columns.reduce(0) { $0 + $1.1 }))

for provider in providers {
    await provider.startMonitoring()
    do {
        let usage = try await provider.fetchUsage()
        if usage.windows.isEmpty {
            // Say *why*, not just that there is nothing. A bare "no windows" sends you
            // reading adapter source to distinguish "signed out" from "schema moved".
            print(
                pad(provider.displayName, 10)
                + pad("—", 18) + pad("—", 8) + pad("—", 24)
                + pad(usage.status.rawValue, 13)
            )
            var detail = ["\(usage.failure ?? "no reason given")", "source: \(usage.source.rawValue)"]
            // Adapter diagnostics — which store answered, what schema arrived. Field names
            // and locations only; the adapters never put a value in here.
            for key in ["credentialSource", "storedExpiry", "storedExpiryPassed", "endpointDetail", "httpStatus", "credentialReadDetail", "schemaUnknownKeys"] {
                if let value = usage.metadata[key] { detail.append("\(key): \(value)") }
            }
            print(pad("", 10) + "└─ " + detail.joined(separator: "  ·  "))
        }
        for window in usage.windows {
            print(
                pad(provider.displayName, 10)
                + pad(window.label, 18)
                + pad(window.usedPercentage.map { String(format: "%.0f%%", $0) } ?? "—", 8)
                + pad(ResetCalculator.resetPhrase(to: window.resetDate, from: now) ?? "—", 24)
                + pad(window.level?.rawValue ?? usage.status.rawValue, 13)
            )
        }
        var extras: [String] = []
        if let plan = usage.plan { extras.append("plan: \(plan)") }
        if let credits = usage.credits {
            if let count = credits.resetCreditsAvailable, count > 0 {
                extras.append("reset credits: \(count)")
            }
            if credits.unlimited { extras.append("unlimited credits") }
        }
        if staleness.isStale(usage, now: now) { extras.append("STALE") }
        if !extras.isEmpty { print(pad("", 10) + "└─ " + extras.joined(separator: "  ·  ")) }
    } catch let error as ProviderError {
        print(pad(provider.displayName, 10) + pad("—", 18) + pad("—", 8)
              + pad("—", 24) + "unavailable")
        print(pad("", 10) + "└─ \(error.userFacingDescription)")
    } catch {
        print(pad(provider.displayName, 10) + "unexpected failure")
    }
    await provider.stopMonitoring()
}
print("")

// MARK: Credential health
//
// Reports what the local credential stores hold, WITHOUT calling any endpoint. Separated
// deliberately: once an endpoint starts rate-limiting, a 429 masks the auth state, and
// asking it again to find out only extends the limit. Credential freshness is knowable
// locally and costs nothing.
//
// Prints locations, scopes and timestamps. Never a token.
if ProcessInfo.processInfo.environment["SIDENOTCH_PROBE_CREDS"] == "1" {
    print("── Credential health (no network) ───────────────────────────────────────")

    let iso = ISO8601DateFormatter()
    do {
        let credential = try ClaudeCredentialSource().read()
        let expiry = credential.expiresAt.map { iso.string(from: $0) } ?? "not stated"
        print("""
          Claude
            store          : \(credential.origin.rawValue)
            scopes         : \(credential.scopes.joined(separator: ", "))
            usage scope    : \(credential.grantsUsageRead ? "granted" : "MISSING user:profile")
            token length   : \(credential.accessToken.count) chars
            stored expiry  : \(expiry)
            expired now    : \(credential.isExpired())
        """)
    } catch {
        print("  Claude\n    unreadable: \(error)")
    }

    do {
        let credential = try CursorCredentialSource().read()
        let expiry = credential.expiresAt.map { iso.string(from: $0) } ?? "not stated"
        print("""
          Cursor
            store          : state.vscdb
            token length   : \(credential.accessToken.count) chars
            stored expiry  : \(expiry)
            expired now    : \(credential.isExpired())
        """)
    } catch {
        print("  Cursor\n    unreadable: \(error)")
    }
    print("")
}

// MARK: Schema inspection
//
// Prints the SHAPE of a provider response — key names and value types, never values — for
// endpoints we are evaluating or watching for drift. Opt-in because it spends a request
// against endpoints that rate-limit.
//
// This is how an adapter gets written against ground truth instead of against a blog post:
// ask the endpoint what it actually returns, then write the decoder to match.
if ProcessInfo.processInfo.environment["SIDENOTCH_PROBE_SCHEMA"] == "1" {
    func describe(_ value: Any, indent: Int = 2) {
        let pad = String(repeating: " ", count: indent)
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                let child = dictionary[key]!
                if child is [String: Any] || child is [Any] {
                    print("\(pad)\(key): \(child is [Any] ? "array" : "object")")
                    describe(child, indent: indent + 2)
                } else {
                    // Numbers and booleans are usage figures — safe and useful to see.
                    // Strings could carry an identifier, so only their type is printed —
                    // except timestamps, whose format has to be known to parse them and
                    // which identify nobody.
                    let isTimestamp = ["cycle", "date", "time", "reset", "expir"]
                        .contains { key.lowercased().contains($0) }
                    let rendered = (child is String && !isTimestamp) ? "string" : "\(child)"
                    print("\(pad)\(key): \(rendered)")
                }
            }
        } else if let array = value as? [Any] {
            print("\(pad)[\(array.count) items]")
            if let first = array.first { describe(first, indent: indent + 2) }
        }
    }

    let candidates = [
        "https://api2.cursor.sh/auth/usage",
        "https://cursor.com/api/usage-summary",
    ]

    // Connect RPC. POST-only even for reads, empty body, and crucially bearer-authenticated
    // rather than cookie-authenticated — so it stays inside the boundary this project drew
    // (reuse the client's credential as a client; never reconstruct the browser's).
    let rpcCandidates = [
        "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
        "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo",
    ]

    print("── Cursor endpoint schemas ──────────────────────────────────────────────")
    do {
        let credential = try CursorCredentialSource().read()
        let http = UsageHTTPClient()
        for endpoint in candidates {
            guard let url = URL(string: endpoint) else { continue }
            let outcome = await http.get(url, headers: [
                "Authorization": "Bearer \(credential.accessToken.reveal())",
                "Accept": "application/json",
            ])
            switch outcome {
            case .success(let data):
                print("\n\(endpoint)  →  200")
                if let root = try? JSONSerialization.jsonObject(with: data) {
                    describe(root)
                } else {
                    print("  (not JSON, \(data.count) bytes)")
                }
            case .unauthorized:      print("\n\(endpoint)  →  401 (bearer not accepted)")
            case .rateLimited:       print("\n\(endpoint)  →  429")
            case .http(let status):  print("\n\(endpoint)  →  \(status)")
            case .transport(let d):  print("\n\(endpoint)  →  \(d)")
            }
        }

        for endpoint in rpcCandidates {
            guard let url = URL(string: endpoint) else { continue }
            let outcome = await http.post(url, headers: [
                "Authorization": "Bearer \(credential.accessToken.reveal())",
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
            ], body: Data("{}".utf8))
            let name = endpoint.split(separator: "/").last.map(String.init) ?? endpoint
            switch outcome {
            case .success(let data):
                print("\n\(name)  →  200")
                if let root = try? JSONSerialization.jsonObject(with: data) {
                    describe(root)
                } else {
                    print("  (not JSON, \(data.count) bytes)")
                }
            case .unauthorized:      print("\n\(name)  →  401 (bearer not accepted)")
            case .rateLimited:       print("\n\(name)  →  429")
            case .http(let status):  print("\n\(name)  →  \(status)")
            case .transport(let d):  print("\n\(name)  →  \(d)")
            }
        }
    } catch {
        print("  no Cursor credential: \(error)")
    }
    print("")
}
