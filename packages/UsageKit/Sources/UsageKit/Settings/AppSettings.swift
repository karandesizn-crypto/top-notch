import Foundation
import Observation
import SwiftUI
import SideNotchCore

/// Appearance override for the surface and its windows.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, dark, light
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        }
    }
}

/// A provider the user added by hand.
public struct CustomProviderDefinition: Codable, Identifiable, Hashable, Sendable {
    /// `ProviderType.rawValue`.
    public let id: String
    public var name: String

    public var providerType: ProviderType { ProviderType(id) }
}

/// User preferences, persisted to `UserDefaults`.
///
/// Deliberately not SwiftData: these are a handful of scalars read on every render, and
/// none is a secret. SwiftData holds the snapshot cache, where the record shape matters.
@Observable
@MainActor
public final class AppSettings {
    /// Refresh bounds. The floor exists because each refresh is a round trip to a local
    /// process the user is also using; polling it hard would be rude.
    public static let minimumRefreshInterval: TimeInterval = 30
    public static let maximumRefreshInterval: TimeInterval = 3600
    /// Cap on the row, so the tab cannot grow wider than the display it hangs from.
    public static let maximumProviders = 6

    public var enabledProviders: Set<ProviderType> {
        didSet { store(enabledProviders.map(\.rawValue), .enabledProviders) }
    }
    public var customProviders: [CustomProviderDefinition] {
        didSet { storeCustomProviders() }
    }
    public var launchAtLogin: Bool { didSet { store(launchAtLogin, .launchAtLogin) } }
    public var refreshInterval: TimeInterval {
        didSet {
            refreshInterval = min(max(refreshInterval, Self.minimumRefreshInterval),
                                 Self.maximumRefreshInterval)
            store(refreshInterval, .refreshInterval)
        }
    }
    public var showPercentages: Bool { didSet { store(showPercentages, .showPercentages) } }
    public var showResetCountdown: Bool { didSet { store(showResetCountdown, .showResetCountdown) } }
    /// Stored as percentages for legibility in defaults; exposed as fractions.
    public var warningThreshold: Double { didSet { store(warningThreshold, .warningThreshold) } }
    public var criticalThreshold: Double { didSet { store(criticalThreshold, .criticalThreshold) } }
    public var notificationsEnabled: Bool { didSet { store(notificationsEnabled, .notificationsEnabled) } }
    public var appearance: AppearanceMode { didSet { store(appearance.rawValue, .appearance) } }
    /// Show the surface on displays with no camera housing.
    ///
    /// Off by default: with nothing to attach to, the surface floats over whatever window
    /// sits at the top edge. On by choice for Macs that have no notch at all, where it is
    /// the only way to see the surface.
    public var showsWithoutNotch: Bool {
        didSet { store(showsWithoutNotch, .showsWithoutNotch) }
    }

    public var thresholds: UsageThresholds {
        UsageThresholds(warning: warningThreshold / 100, critical: criticalThreshold / 100)
    }

    /// Every provider that could appear, built-ins first then the user's own.
    public var allProviders: [ProviderType] {
        ProviderType.builtIn + customProviders.map(\.providerType)
    }

    private let defaults: UserDefaults

    private enum Key: String {
        case enabledProviders, customProviders, launchAtLogin, refreshInterval
        case showPercentages, showResetCountdown, warningThreshold, criticalThreshold
        case notificationsEnabled, appearance, showsWithoutNotch
    }

    public init(defaults: UserDefaults = .standard) {
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
            enabledProviders = Set(raw.map { ProviderType($0) })
        } else {
            enabledProviders = Set(ProviderType.builtIn)
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
        showsWithoutNotch = defaults.object(forKey: Key.showsWithoutNotch.rawValue) as? Bool ?? false
    }

    public func isEnabled(_ provider: ProviderType) -> Bool { enabledProviders.contains(provider) }

    public func setEnabled(_ enabled: Bool, for provider: ProviderType) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
    }

    public func displayName(for provider: ProviderType) -> String {
        customProviders.first { $0.id == provider.rawValue }?.name
            ?? provider.defaultDisplayName
    }

    /// Adds a provider by title. Returns nil when the title is empty or already taken.
    @discardableResult
    public func addCustomProvider(named title: String) -> ProviderType? {
        let slug = ProviderType.slug(from: title)
        guard !slug.isEmpty else { return nil }
        let id = ProviderType(slug)
        guard !allProviders.contains(id) else { return nil }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        customProviders.append(CustomProviderDefinition(id: slug, name: trimmed))
        enabledProviders.insert(id)
        return id
    }

    public func removeCustomProvider(_ provider: ProviderType) {
        customProviders.removeAll { $0.id == provider.rawValue }
        enabledProviders.remove(provider)
    }

    /// Whether another provider can be shown without the tab outgrowing the display.
    public var canAddProvider: Bool { allProviders.count < Self.maximumProviders }

    /// Keeps critical at or above warning, so the two can never invert.
    public func normalizeThresholds() {
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
