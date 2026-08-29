import Foundation
import Observation
import SwiftUI
import SideNotchCore

/// Appearance override for the rail and its windows.
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

/// User preferences, persisted to `UserDefaults`.
///
/// Deliberately not SwiftData: these are a handful of scalars read on every render, and
/// none of them is a secret. SwiftData is used for the snapshot cache, where the record
/// shape actually matters.
@Observable
@MainActor
final class AppSettings {
    /// Refresh bounds. The floor exists because each refresh is a JSON-RPC round trip to a
    /// local process the user is also using; polling it aggressively would be rude.
    static let minimumRefreshInterval: TimeInterval = 30
    static let maximumRefreshInterval: TimeInterval = 3600

    var enabledProviders: Set<ProviderID> {
        didSet { store(Array(enabledProviders.map(\.rawValue)), .enabledProviders) }
    }
    var launchAtLogin: Bool {
        didSet { store(launchAtLogin, .launchAtLogin) }
    }
    var refreshInterval: TimeInterval {
        didSet {
            refreshInterval = min(max(refreshInterval, Self.minimumRefreshInterval), Self.maximumRefreshInterval)
            store(refreshInterval, .refreshInterval)
        }
    }
    var showPercentages: Bool {
        didSet { store(showPercentages, .showPercentages) }
    }
    var showResetCountdown: Bool {
        didSet { store(showResetCountdown, .showResetCountdown) }
    }
    /// Stored as percentages for legibility in defaults; exposed as fractions.
    var warningThreshold: Double {
        didSet { store(warningThreshold, .warningThreshold) }
    }
    var criticalThreshold: Double {
        didSet { store(criticalThreshold, .criticalThreshold) }
    }
    var notificationsEnabled: Bool {
        didSet { store(notificationsEnabled, .notificationsEnabled) }
    }
    var appearance: AppearanceMode {
        didSet { store(appearance.rawValue, .appearance) }
    }

    var thresholds: UsageThresholds {
        UsageThresholds(warning: warningThreshold / 100, critical: criticalThreshold / 100)
    }

    private let defaults: UserDefaults

    private enum Key: String {
        case enabledProviders, launchAtLogin, refreshInterval, showPercentages
        case showResetCountdown, warningThreshold, criticalThreshold
        case notificationsEnabled, appearance
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Only Codex has a live integration; the others default off so a fresh install is
        // not a rail of "unsupported" rings.
        if let raw = defaults.array(forKey: Key.enabledProviders.rawValue) as? [String] {
            enabledProviders = Set(raw.compactMap(ProviderID.init(rawValue:)))
        } else {
            enabledProviders = [.codex]
        }

        launchAtLogin = defaults.object(forKey: Key.launchAtLogin.rawValue) as? Bool ?? false
        let storedInterval = defaults.object(forKey: Key.refreshInterval.rawValue) as? Double ?? 300
        refreshInterval = min(max(storedInterval, Self.minimumRefreshInterval), Self.maximumRefreshInterval)
        showPercentages = defaults.object(forKey: Key.showPercentages.rawValue) as? Bool ?? true
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

    /// Keeps critical at or above warning, so the two can never invert.
    func normalizeThresholds() {
        if criticalThreshold < warningThreshold { criticalThreshold = warningThreshold }
    }

    private func store(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
