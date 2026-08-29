import SwiftUI
import SideNotchCore
import ProviderKit

/// The settings window.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: UsageStore
    let onSettingsChanged: () -> Void

    var body: some View {
        TabView {
            providersTab.tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            notificationsTab.tabItem { Label("Notifications", systemImage: "bell") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 460, height: 340)
    }

    // MARK: Providers

    private var providersTab: some View {
        Form {
            Section {
                ForEach(store.order, id: \.self) { provider in
                    providerRow(provider)
                }
            } footer: {
                Text("Only providers with a supported local interface can report usage. "
                     + "Claude and Cursor are listed so they can be enabled the moment one exists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func providerRow(_ provider: ProviderID) -> some View {
        let status = store.status(for: provider)
        Toggle(isOn: Binding(
            get: { settings.isEnabled(provider) },
            set: { settings.setEnabled($0, for: provider); onSettingsChanged() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status?.displayName ?? provider.displayName)
                if let message = status?.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                } else if let window = status?.headlineWindow,
                          let percentage = window.usedPercentage {
                    Text("\(window.label) · \(Int(percentage.rounded()))% used")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0; LaunchAtLogin.set($0) }
                ))
                if !LaunchAtLogin.isSupported {
                    Text("Available once SideNotch is running from an app bundle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Refresh every", selection: Binding(
                    get: { settings.refreshInterval },
                    set: { settings.refreshInterval = $0; onSettingsChanged() }
                )) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("15 minutes").tag(TimeInterval(900))
                    Text("1 hour").tag(TimeInterval(3600))
                }
            } footer: {
                Text("Codex also pushes updates as they happen, so a longer interval is "
                     + "usually fine.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show percentages on the rail", isOn: $settings.showPercentages)
                Toggle("Show reset countdown", isOn: $settings.showResetCountdown)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Notifications

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
                if !NotificationService.isAvailable {
                    Text("Available once SideNotch is running from an app bundle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Thresholds") {
                thresholdSlider("Warning", value: $settings.warningThreshold)
                thresholdSlider("Critical", value: $settings.criticalThreshold)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.warningThreshold) { settings.normalizeThresholds(); onSettingsChanged() }
        .onChange(of: settings.criticalThreshold) { settings.normalizeThresholds(); onSettingsChanged() }
    }

    private func thresholdSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            Slider(value: value, in: 50...99, step: 1)
            Text("\(Int(value.wrappedValue))%")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: Appearance

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: Binding(
                get: { settings.appearance },
                set: { settings.appearance = $0; onSettingsChanged() }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }
}
