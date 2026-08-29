import Foundation
import SideNotchCore
import ProviderKit

// Phase 0 exit gate: prove every adapter returns real, correctly normalized readings
// before any UI is built on top of them.

let providers: [any UsageProvider] = [
    ClaudeProvider(),
    CodexProvider(),
    CursorProvider(),
]

let policy = StalenessPolicy.default
let now = Date()

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func ageDescription(since date: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    if seconds < 90 { return "\(max(seconds, 0))s ago" }
    if seconds < 5400 { return "\(seconds / 60)m ago" }
    if seconds < 172_800 { return "\(seconds / 3600)h ago" }
    return "\(seconds / 86400)d ago"
}

let columns = [("PROVIDER", 10), ("WINDOW", 22), ("USED", 8), ("RESETS IN", 12),
               ("HEALTH", 14), ("SOURCE", 11), ("OBSERVED", 10)]
print("")
print(columns.map { pad($0.0, $0.1) }.joined())
print(String(repeating: "─", count: columns.reduce(0) { $0 + $1.1 }))

var rows = 0
var live = 0

for provider in providers {
    do {
        let snapshots = try await provider.fetchSnapshots()
        for snapshot in snapshots {
            rows += 1
            let stale = policy.isStale(snapshot, now: now)
            if snapshot.percentageUsed != nil && !stale { live += 1 }

            let used = snapshot.percentageUsed.map { String(format: "%.0f%%", $0) } ?? "—"
            let reset = ResetCalculator.countdown(to: snapshot.resetAt, from: now) ?? "—"
            let health = stale ? "\(snapshot.health.rawValue)*" : snapshot.health.rawValue

            print(
                pad(snapshot.provider.displayName, 10)
                + pad(snapshot.windowLabel ?? snapshot.scope.rawValue, 22)
                + pad(used, 8)
                + pad(reset, 12)
                + pad(health, 14)
                + pad(snapshot.source.rawValue, 11)
                + pad(ageDescription(since: snapshot.observedAt), 10)
            )
            if let detail = snapshot.detail {
                print(pad("", 10) + "└─ \(detail)")
            }
        }
    } catch {
        print(pad(provider.id.displayName, 10) + "read failed: \(error.localizedDescription)")
    }
}

print("")
print("\(rows) snapshot(s); \(live) with a live percentage.  * = stale, older than \(Int(policy.maxAge / 60))m")
