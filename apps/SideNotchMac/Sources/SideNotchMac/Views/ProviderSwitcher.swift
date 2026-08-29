import SwiftUI
import SideNotchCore

/// Compact provider selector for the expanded surface.
///
/// Built from whatever providers are enabled, so nothing about which providers exist is
/// baked into the view hierarchy — adding a provider to `ProviderID` and enabling it in
/// settings is enough.
struct ProviderSwitcher: View {
    let providers: [ProviderID]
    let selected: ProviderID
    let stateFor: (ProviderID) -> UsageState
    let displayNameFor: (ProviderID) -> String
    let onSelect: (ProviderID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(providers, id: \.self) { provider in
                item(provider)
            }
        }
    }

    private func item(_ provider: ProviderID) -> some View {
        let isSelected = provider == selected
        let name = displayNameFor(provider)

        return Button {
            onSelect(provider)
        } label: {
            VStack(spacing: 4) {
                Text(name)
                    .font(Tokens.Type_.switcher)
                    .foregroundStyle(
                        isSelected ? Tokens.Palette.primaryText : Tokens.Palette.tertiaryText
                    )
                    .lineLimit(1)

                Circle()
                    .fill(Tokens.Palette.color(for: stateFor(provider)))
                    .frame(width: 5, height: 5)
                    .opacity(isSelected ? 1 : 0.5)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        // The selection pill slides between providers rather than
                        // cross-fading, so switching reads as one object moving.
                        .matchedGeometryEffect(id: "selection", in: indicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: selected)
        .accessibilityLabel("\(name) provider")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
