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
            print(pad(provider.displayName, 10) + "no metered windows reported")
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
