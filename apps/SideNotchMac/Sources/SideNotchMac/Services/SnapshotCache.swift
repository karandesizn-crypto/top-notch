import Foundation
import SwiftData
import ProviderKit
import SideNotchCore

/// Last known snapshot per provider, so the rail shows something on launch instead of
/// three empty rings while the first refresh runs.
///
/// The snapshot is stored as encoded JSON rather than a relational model: `UsageSnapshot`
/// already round-trips through `Codable`, its window list is variable-length by design,
/// and a schema mirroring it would have to migrate every time a provider adds a field.
@Model
final class CachedSnapshot {
    /// `ProviderID.rawValue`. Unique so each provider keeps exactly one row.
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
final class SnapshotCache {
    private let container: ModelContainer?
    private let context: ModelContext?

    init(inMemory: Bool = false) {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
            let container = try ModelContainer(for: CachedSnapshot.self, configurations: configuration)
            self.container = container
            self.context = ModelContext(container)
        } catch {
            Log.app.error("snapshot cache unavailable; continuing without it")
            self.container = nil
            self.context = nil
        }
    }

    func load() -> [ProviderID: UsageSnapshot] {
        guard let context else { return [:] }
        let descriptor = FetchDescriptor<CachedSnapshot>()
        guard let rows = try? context.fetch(descriptor) else { return [:] }

        var result: [ProviderID: UsageSnapshot] = [:]
        for row in rows {
            guard let id = ProviderID(rawValue: row.providerID),
                  let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: row.payload)
            else { continue }
            result[id] = snapshot
        }
        return result
    }

    func save(_ snapshot: UsageSnapshot) {
        guard let context, let payload = try? JSONEncoder().encode(snapshot) else { return }
        let key = snapshot.provider.rawValue
        let descriptor = FetchDescriptor<CachedSnapshot>(
            predicate: #Predicate { $0.providerID == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.storedAt = snapshot.lastUpdated
        } else {
            context.insert(
                CachedSnapshot(providerID: key, payload: payload, storedAt: snapshot.lastUpdated)
            )
        }
        try? context.save()
    }
}
