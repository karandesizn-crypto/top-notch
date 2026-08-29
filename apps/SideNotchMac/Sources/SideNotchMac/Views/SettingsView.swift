import SwiftUI
import SideNotchCore
import ProviderKit

/// The settings window.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: UsageStore
    let onSettingsChanged: () -> Void
    let onProvidersChanged: () -> Void

    @State private var newProviderName = ""

    var body: some View {
        TabView {
            providersTab.tabItem { Label("Providers", systemImage: "square.stack.3d.up") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            notificationsTab.tabItem { Label("Notifications", systemImage: "bell") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintbrush") }
        }
        .frame(width: 470, height: 380)
    }

    // MARK: Providers

    private var providersTab: some View {
        Form {
            Section("Built in") {
                ForEach(ProviderID.builtIn) { provider in
                    providerRow(provider)
                }
            }

            Section {
                ForEach(settings.customProviders) { definition in
                    HStack {
                        providerRow(definition.providerID)
                        Button {
                            settings.removeCustomProvider(definition.providerID)
                            onProvidersChanged()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(definition.name)")
                    }
                }

                HStack {
                    TextField("Add a tool, e.g. Antigravity", text: $newProviderName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addProvider)
                    Button("Add", action: addProvider)
                        .disabled(!canAdd)
                }
            } header: {
                Text("Your tools")
            } footer: {
                Text(settings.canAddProvider
                     ? "Added tools appear in the row and are marked unavailable until an "
                       + "integration exists for them. Only Codex reports live usage today."
                     : "The row holds up to \(AppSettings.maximumProviders) tools.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var canAdd: Bool {
        settings.canAddProvider
            && !ProviderID.slug(from: newProviderName).isEmpty
            && !settings.allProviders.contains(ProviderID(ProviderID.slug(from: newProviderName)))
    }

    private func addProvider() {
        guard canAdd, settings.addCustomProvider(named: newProviderName) != nil else { return }
        newProviderName = ""
        onProvidersChanged()
    }

    @ViewBuilder
    private func providerRow(_ provider: ProviderID) -> some View {
        let status = store.status(for: provider)
        Toggle(isOn: Binding(
            get: { settings.isEnabled(provider) },
            set: { settings.setEnabled($0, for: provider); onSettingsChanged() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.displayName(for: provider))
                if let window = status?.headlineWindow, let percentage = window.usedPercentage {
                    Text("\(window.label) · \(Int(percentage.rounded()))% used")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let message = status?.statusMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
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
                Toggle("Show percentages in the collapsed tab", isOn: $settings.showPercentages)
                Toggle("Show reset countdown", isOn: $settings.showResetCountdown)
            }

            Section {
                Toggle("Show on displays without a notch", isOn: Binding(
                    get: { settings.showsWithoutNotch },
                    set: { settings.showsWithoutNotch = $0; onSettingsChanged() }
                ))
            } footer: {
                Text("SideNotch lives in the camera notch. On a display without one it has "
                     + "nothing to attach to, so it stays hidden and the menu bar item is "
                     + "the way in. Turn this on if your Mac has no notch at all.")
                    .font(.caption).foregroundStyle(.secondary)
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

            Section {
                thresholdSlider("Warning", value: $settings.warningThreshold)
                thresholdSlider("Critical", value: $settings.criticalThreshold)
            } header: {
                Text("Thresholds")
            } footer: {
                Text("These set both the ring colour and when alerts fire. Each window "
                     + "notifies once per escalation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.warningThreshold) { settings.normalizeThresholds(); onSettingsChanged() }
        .onChange(of: settings.criticalThreshold) { settings.normalizeThresholds(); onSettingsChanged() }
    }

    private func thresholdSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            Slider(value: value, in: 20...99, step: 1)
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
