import SwiftUI
import SideNotchCore

/// The rail plus its fly-out card.
///
/// The card is laid out to the left of the slab inside the same panel. The panel is always
/// full width — `PassthroughContentView` makes the empty region click-through — so showing
/// the card never costs a window resize, and the pointer can travel from ring to card
/// without crossing a gap that would dismiss it.
struct RailView: View {
    @Bindable var store: UsageStore
    @Binding var focused: ProviderID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardHeight: CGFloat = 0
    @State private var hoveredRing: ProviderID?
    @State private var isCardHovered = false

    private var geometry: RailGeometry {
        Tokens.Rail.geometry(itemCount: store.order.count)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let focused {
                DetailCard(
                    provider: focused,
                    snapshots: store.snapshots(for: focused),
                    tailCenterY: tailCenterY(for: focused),
                    staleness: store.staleness,
                    now: store.now
                )
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: CardHeightKey.self, value: geometry.size.height)
                    }
                }
                .offset(y: cardOffset(for: focused))
                .padding(.trailing, Tokens.Card.railGap)
                .onHover { isCardHovered = $0; resolveFocus() }
                .transition(.opacity.combined(with: .offset(x: 14)))
            }

            VStack(spacing: 0) {
                ForEach(store.order, id: \.self) { provider in
                    let snapshot = store.headline(for: provider)
                    UsageRing(
                        snapshot: snapshot,
                        provider: provider,
                        isStale: store.isStale(snapshot),
                        isFocused: focused == provider
                    )
                    .onHover { hovering in
                        hoveredRing = hovering ? provider : (hoveredRing == provider ? nil : hoveredRing)
                        resolveFocus()
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

    /// Focus follows the ring under the pointer, and survives the pointer moving onto the
    /// card — otherwise the card would vanish the moment you tried to read it.
    private func resolveFocus() {
        let next = hoveredRing ?? (isCardHovered ? focused : nil)
        guard next != focused else { return }
        withAnimation(Tokens.Motion.expand(reduceMotion: reduceMotion)) { focused = next }
    }

    /// Rail geometry is computed by `RailGeometry` in SideNotchCore, where it is unit
    /// tested — a tail that points at empty space renders perfectly happily, so this
    /// arithmetic is worth testing away from a running app.
    private func cardOffset(for provider: ProviderID) -> CGFloat {
        guard let index = store.order.firstIndex(of: provider) else { return 0 }
        return geometry.cardOffset(index: index, cardHeight: cardHeight)
    }

    private func tailCenterY(for provider: ProviderID) -> CGFloat {
        guard let index = store.order.firstIndex(of: provider) else { return 0 }
        return geometry.tailCenterY(index: index, cardHeight: cardHeight)
    }
}

private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
