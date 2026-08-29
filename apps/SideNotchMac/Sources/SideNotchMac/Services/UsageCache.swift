import Foundation
import SwiftData
import ProviderKit
import SideNotchCore

/// Last known reading per provider, so the surface shows something on launch instead of
/// empty rings while the first refresh runs.
///
/// Restored readings come back marked `.cached`, never `.live` — provenance has to survive
/// a relaunch, or a figure from yesterday presents as current.
///
/// The state is stored as encoded JSON rather than a relational model: `UsageState`
/// already round-trips through `Codable`, its window list is variable-length by design,
/// and a schema mirroring it would have to migrate every time a provider adds a field.
@Model
final class CachedUsage {
    /// `ProviderType.rawValue`. Unique so each provider keeps exactly one row.
    @Attribute(.unique) var providerID: String
    var payload: Data
    var storedAt: Date

    init(providerID: String, payload: Data, storedAt: Date) {
        self.providerID = providerID
        self.payload = payload
        self.storedAt = storedAt
    }
}

/// Reads and writes the snapshot cache.
///
/// Every operation degrades to a no-op on failure: a broken cache must never stop the app
/// from showing live data.
@MainActor
final class UsageCache {
    private let container: ModelContainer?
    private let context: ModelContext?

    init(inMemory: Bool = false) {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            let container = try ModelContainer(for: CachedUsage.self, configurations: configuration)
            self.container = container
            self.context = ModelContext(container)
        } catch {
            Log.app.error("snapshot cache unavailable; continuing without it")
            self.container = nil
            self.context = nil
        }
    }

    func load() -> [ProviderType: UsageState] {
        guard let context else { return [:] }
        let descriptor = FetchDescriptor<CachedUsage>()
        guard let rows = try? context.fetch(descriptor) else { return [:] }

        var result: [ProviderType: UsageState] = [:]
        for row in rows {
            // Any identifier is valid now that providers can be user-added, so only the
            // payload can fail to decode.
            guard let state = try? JSONDecoder().decode(
                UsageState.self, from: row.payload
            ) else { continue }
            // Marked as cached on the way out, so a restored reading never presents as live.
            result[ProviderType(row.providerID)] = state.asCached()
        }
        return result
    }

    func save(_ state: UsageState) {
        // Only genuine readings are worth persisting; an unsupported or failed state
        // carries nothing to restore and would only mask the next real attempt.
        guard state.status == .available, let context,
              let payload = try? JSONEncoder().encode(state) else { return }
        let key = state.provider.rawValue
        let descriptor = FetchDescriptor<CachedUsage>(
            predicate: #Predicate { $0.providerID == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.storedAt = state.lastUpdated ?? Date()
        } else {
            context.insert(
                CachedUsage(providerID: key, payload: payload, storedAt: state.lastUpdated ?? Date())
            )
        }
        try? context.save()
    }
}
