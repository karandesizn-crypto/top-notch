import SwiftUI
import SideNotchCore

/// The rail plus its fly-out card.
///
/// The panel is always full width and `PassthroughContentView` makes the empty region
/// click-through, so the card appears without a window resize and the pointer can travel
/// from ring to card without crossing a gap that would dismiss it.
struct RailView: View {
    @Bindable var store: UsageStore
    @Bindable var settings: AppSettings
    @Binding var focused: ProviderID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardHeight: CGFloat = 0
    @State private var hoveredRing: ProviderID?
    @State private var isCardHovered = false

    private var providers: [ProviderID] { store.visibleProviders }

    private var geometry: RailGeometry {
        Tokens.Rail.geometry(itemCount: max(providers.count, 1))
    }

    private var containerHeight: CGFloat {
        Tokens.Rail.panelHeight(itemCount: max(providers.count, 1))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let focused, let status = store.status(for: focused) {
                DetailCard(
                    status: status,
                    tailCenterY: tailCenterY(for: focused),
                    isStale: store.isStale(focused),
                    showResetCountdown: settings.showResetCountdown,
                    now: store.now
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: CardHeightKey.self, value: proxy.size.height)
                    }
                }
                .offset(y: cardOffset(for: focused))
                .padding(.trailing, Tokens.Card.railGap)
                .onHover { isCardHovered = $0; resolveFocus() }
                .transition(.opacity.combined(with: .offset(x: 14)))
            }

            VStack(spacing: 0) {
                ForEach(providers, id: \.self) { provider in
                    if let status = store.status(for: provider) {
                        UsageRing(
                            status: status,
                            isStale: store.isStale(provider),
                            isFocused: focused == provider,
                            showPercentage: settings.showPercentages
                        )
                        .onHover { hovering in
                            hoveredRing = hovering
                                ? provider
                                : (hoveredRing == provider ? nil : hoveredRing)
                            resolveFocus()
                        }
                    }
                }
            }
            .padding(.vertical, Tokens.Rail.verticalPadding)
            .frame(width: Tokens.Rail.width)
            .background {
                NotchShape()
                    .fill(Tokens.Palette.surface)
                    .shadow(color: .black.opacity(0.35), radius: 10, x: -3, y: 3)
            }
        }
        .onPreferenceChange(CardHeightKey.self) { cardHeight = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    /// Focus follows the ring under the pointer and survives the pointer moving onto the
    /// card — otherwise the card would vanish as soon as you tried to read it.
    private func resolveFocus() {
        let next = hoveredRing ?? (isCardHovered ? focused : nil)
        guard next != focused else { return }
        withAnimation(Tokens.Motion.expand(reduceMotion: reduceMotion)) { focused = next }
    }

    /// Rail arithmetic lives in `RailGeometry` in SideNotchCore, where it is unit tested:
    /// a tail pointing at empty space renders perfectly happily.
    private func cardOffset(for provider: ProviderID) -> CGFloat {
        guard let index = providers.firstIndex(of: provider) else { return 0 }
        return geometry.cardOffset(
            index: index, cardHeight: cardHeight, containerHeight: containerHeight
        )
    }

    private func tailCenterY(for provider: ProviderID) -> CGFloat {
        guard let index = providers.firstIndex(of: provider) else { return 0 }
        return geometry.tailCenterY(
            index: index, cardHeight: cardHeight, containerHeight: containerHeight
        )
    }
}

private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
