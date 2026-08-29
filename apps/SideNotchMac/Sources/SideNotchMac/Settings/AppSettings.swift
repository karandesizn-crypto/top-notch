import Foundation
import Observation
import SwiftUI
import SideNotchCore

/// Appearance override for the surface and its windows.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, dark, light
    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

/// A provider the user added by hand.
struct CustomProviderDefinition: Codable, Identifiable, Hashable, Sendable {
    /// `ProviderID.rawValue`.
    let id: String
    var name: String

    var providerID: ProviderID { ProviderID(id) }
}

/// User preferences, persisted to `UserDefaults`.
///
/// Deliberately not SwiftData: these are a handful of scalars read on every render, and
/// none is a secret. SwiftData holds the snapshot cache, where the record shape matters.
@Observable
@MainActor
final class AppSettings {
    /// Refresh bounds. The floor exists because each refresh is a round trip to a local
    /// process the user is also using; polling it hard would be rude.
    static let minimumRefreshInterval: TimeInterval = 30
    static let maximumRefreshInterval: TimeInterval = 3600
    /// Cap on the row, so the tab cannot grow wider than the display it hangs from.
    static let maximumProviders = 6

    var enabledProviders: Set<ProviderID> {
        didSet { store(enabledProviders.map(\.rawValue), .enabledProviders) }
    }
    var customProviders: [CustomProviderDefinition] {
        didSet { storeCustomProviders() }
    }
    var launchAtLogin: Bool { didSet { store(launchAtLogin, .launchAtLogin) } }
    var refreshInterval: TimeInterval {
        didSet {
            refreshInterval = min(max(refreshInterval, Self.minimumRefreshInterval),
                                 Self.maximumRefreshInterval)
            store(refreshInterval, .refreshInterval)
        }
    }
    var showPercentages: Bool { didSet { store(showPercentages, .showPercentages) } }
    var showResetCountdown: Bool { didSet { store(showResetCountdown, .showResetCountdown) } }
    /// Stored as percentages for legibility in defaults; exposed as fractions.
    var warningThreshold: Double { didSet { store(warningThreshold, .warningThreshold) } }
    var criticalThreshold: Double { didSet { store(criticalThreshold, .criticalThreshold) } }
    var notificationsEnabled: Bool { didSet { store(notificationsEnabled, .notificationsEnabled) } }
    var appearance: AppearanceMode { didSet { store(appearance.rawValue, .appearance) } }

    var thresholds: UsageThresholds {
        UsageThresholds(warning: warningThreshold / 100, critical: criticalThreshold / 100)
    }

    /// Every provider that could appear, built-ins first then the user's own.
    var allProviders: [ProviderID] {
        ProviderID.builtIn + customProviders.map(\.providerID)
    }

    private let defaults: UserDefaults

    private enum Key: String {
        case enabledProviders, customProviders, launchAtLogin, refreshInterval
        case showPercentages, showResetCountdown, warningThreshold, criticalThreshold
        case notificationsEnabled, appearance
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.data(forKey: Key.customProviders.rawValue),
           let decoded = try? JSONDecoder().decode([CustomProviderDefinition].self, from: raw) {
            customProviders = decoded
        } else {
            customProviders = []
        }

        // The three shipped providers are all on by default: the product's promise is one
        // glance at all of them, and a provider that cannot report yet still says so.
        if let raw = defaults.array(forKey: Key.enabledProviders.rawValue) as? [String] {
            enabledProviders = Set(raw.map { ProviderID($0) })
        } else {
            enabledProviders = Set(ProviderID.builtIn)
        }

        launchAtLogin = defaults.object(forKey: Key.launchAtLogin.rawValue) as? Bool ?? false
        let storedInterval = defaults.object(forKey: Key.refreshInterval.rawValue) as? Double ?? 300
        refreshInterval = min(max(storedInterval, Self.minimumRefreshInterval),
                              Self.maximumRefreshInterval)
        // Off by default: the collapsed tab's job is to be small, and the ring colour
        // already answers "is my usage okay?". Turning it on widens every chip.
        showPercentages = defaults.object(forKey: Key.showPercentages.rawValue) as? Bool ?? false
        showResetCountdown = defaults.object(forKey: Key.showResetCountdown.rawValue) as? Bool ?? true
        // Percentage form of `UsageThresholds.default`.
        warningThreshold = defaults.object(forKey: Key.warningThreshold.rawValue) as? Double ?? 50
        criticalThreshold = defaults.object(forKey: Key.criticalThreshold.rawValue) as? Double ?? 70
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled.rawValue) as? Bool ?? true
        appearance = AppearanceMode(
            rawValue: defaults.string(forKey: Key.appearance.rawValue) ?? ""
        ) ?? .system
    }

    func isEnabled(_ provider: ProviderID) -> Bool { enabledProviders.contains(provider) }

    func setEnabled(_ enabled: Bool, for provider: ProviderID) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
    }

    func displayName(for provider: ProviderID) -> String {
        customProviders.first { $0.id == provider.rawValue }?.name
            ?? provider.defaultDisplayName
    }

    /// Adds a provider by title. Returns nil when the title is empty or already taken.
    @discardableResult
    func addCustomProvider(named title: String) -> ProviderID? {
        let slug = ProviderID.slug(from: title)
        guard !slug.isEmpty else { return nil }
        let id = ProviderID(slug)
        guard !allProviders.contains(id) else { return nil }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        customProviders.append(CustomProviderDefinition(id: slug, name: trimmed))
        enabledProviders.insert(id)
        return id
    }

    func removeCustomProvider(_ provider: ProviderID) {
        customProviders.removeAll { $0.id == provider.rawValue }
        enabledProviders.remove(provider)
    }

    /// Whether another provider can be shown without the tab outgrowing the display.
    var canAddProvider: Bool { allProviders.count < Self.maximumProviders }

    /// Keeps critical at or above warning, so the two can never invert.
    func normalizeThresholds() {
        if criticalThreshold < warningThreshold { criticalThreshold = warningThreshold }
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private func storeCustomProviders() {
        guard let data = try? JSONEncoder().encode(customProviders) else { return }
        defaults.set(data, forKey: Key.customProviders.rawValue)
    }
}
