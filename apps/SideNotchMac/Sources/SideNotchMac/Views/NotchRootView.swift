import SwiftUI
import Observation
import SideNotchCore
import ProviderKit

/// Presentation state of the surface.
@Observable
@MainActor
final class NotchSurfaceState {
    var isExpanded = false
    /// Tucked away to the housing band alone, leaving the screen unobstructed.
    var isMinimized = false
    /// Set by a click. A pinned surface stays open when the pointer leaves, and is
    /// dismissed by Escape or another click.
    var isPinned = false
    var selected: ProviderID = .codex
}

/// The notch surface: a compact tab hanging below the camera housing that opens into a
/// usage panel.
///
/// The chip row is the whole collapsed state and stays exactly where it is when the tab
/// expands — it doubles as the provider switcher rather than being replaced by a second,
/// larger row. Nothing moves on expand; content is only revealed beneath, which is what
/// makes it read as one surface changing shape.
struct NotchRootView: View {
    @Bindable var store: UsageStore
    @Bindable var settings: AppSettings
    @Bindable var surface: NotchSurfaceState
    let layout: NotchSurfaceLayout
    /// Opens settings so another tool can be added.
    var onAddProvider: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { surface.isExpanded }
    private var providers: [ProviderID] { store.visibleProviders }
    private var status: ProviderStatus? { store.status(for: surface.selected) }

    private var minimized: Bool { surface.isMinimized }

    private var size: CGSize {
        SurfaceSizing.size(layout: layout, expanded: expanded, minimized: minimized)
    }

    private var shape: NotchSurfaceShape {
        NotchSurfaceShape(
            flare: layout.flare,
            bottomRadius: expanded ? Tokens.Surface.expandedRadius : Tokens.Surface.collapsedRadius
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        VStack(spacing: 0) {
            chipRow
            if expanded && !minimized {
                snippet
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            shape
                .fill(Tokens.Palette.surface)
                .overlay { shape.stroke(Tokens.Palette.surfaceEdge, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.45), radius: expanded ? 16 : 7, y: expanded ? 7 : 3)
        }
        .clipShape(shape)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: expanded)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: minimized)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: size.height)
        .onHover { hovering in
            // Leaving the tab collapses it. Entering does not expand on its own: a chip
            // has to be hovered, so the card always describes something specific rather
            // than whatever happened to be selected last.
            guard !surface.isPinned, !hovering else { return }
            withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                surface.isExpanded = false
            }
        }
        .onTapGesture { togglePinned() }
        .accessibilityElement(children: expanded ? .contain : .contain)
        .accessibilityLabel("SideNotch usage")
        .accessibilityHint(expanded ? "Click to collapse" : "Click to expand usage details")
    }

    private func togglePinned() {
        withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
            if surface.isPinned {
                surface.isPinned = false
                surface.isExpanded = false
            } else {
                surface.isPinned = true
                surface.isExpanded = true
            }
        }
    }

    // MARK: Collapsed chip row

    /// One chip per provider: a small ring and its figure. This is the entire collapsed
    /// state, and the answer to "is my usage okay?" at a glance.
    /// Items in the provider row: one per provider, then the add button.
    private enum RowItem: Hashable {
        case provider(ProviderID)
        case add
    }

    private var rowItems: [RowItem] {
        providers.map(RowItem.provider) + (layout.showsAddButton ? [.add] : [])
    }

    /// The housing band, then one continuous provider row beneath it.
    ///
    /// The band is empty on purpose: it is the height of the camera, which nothing can be
    /// drawn over. Putting the row below it rather than either side of it is what lets the
    /// providers sit together as one group.
    ///
    /// Hovering the band itself tucks the surface away, so a pass of the pointer over the
    /// notch clears the screen. Toggling on entry rather than continuously means it fires
    /// once per pass instead of flickering while the pointer rests there.
    private var chipRow: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: layout.housingRowHeight)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard hovering, !surface.isPinned else { return }
                    withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                        surface.isMinimized.toggle()
                        if surface.isMinimized { surface.isExpanded = false }
                    }
                }

            if !minimized {
                HStack(spacing: 0) {
                    ForEach(rowItems, id: \.self) { item($0) }
                }
                .frame(height: layout.chipRowHeight)
                .transition(.opacity)
            }
        }
        .frame(height: minimized ? layout.minimizedSize.height : layout.collapsedHeight)
    }

    @ViewBuilder
    private func item(_ item: RowItem) -> some View {
        switch item {
        case .provider(let provider): chip(provider)
        case .add: addButton
        }
    }

    private var addButton: some View {
        Button(action: onAddProvider) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.Palette.secondaryText)
                .frame(width: Tokens.Ring.chipDiameter, height: Tokens.Ring.chipDiameter)
                .background { Circle().fill(Color.white.opacity(0.08)) }
                .frame(width: layout.chipWidth, height: layout.chipRowHeight, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a tool")
    }

    private func chip(_ provider: ProviderID) -> some View {
        let providerStatus = store.status(for: provider)
        let isSelected = expanded && provider == surface.selected

        return Button {
            select(provider)
        } label: {
            VStack(spacing: 5) {
                UsageRing(
                    state: providerStatus?.state ?? .loading,
                    fraction: providerStatus?.headlineWindow?.usedFraction,
                    provider: provider,
                    diameter: Tokens.Ring.chipDiameter,
                    lineWidth: Tokens.Ring.chipLineWidth,
                    glyphSize: Tokens.Ring.chipGlyph
                )
                if settings.showPercentages {
                    Text(caption(for: providerStatus))
                        .font(Tokens.Type_.chipValue)
                        .foregroundStyle(
                            providerStatus?.headlineWindow?.usedFraction == nil
                                ? Tokens.Palette.secondaryText : Tokens.Palette.primaryText
                        )
                        .monospacedDigit()
                }
            }
            .frame(width: layout.chipWidth, height: layout.chipRowHeight, alignment: .top)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                        .padding(.horizontal, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: surface.selected)
        // Hovering a chip is what opens the card, and which chip decides what it shows.
        .onHover { hovering in
            guard hovering, !surface.isPinned, !surface.isMinimized else { return }
            withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                surface.selected = provider
                surface.isExpanded = true
            }
        }
        .accessibilityLabel(label(for: providerStatus))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Expanded detail

    /// Two lines: which provider and window, then the figure and its reset.
    ///
    /// A glance, not a panel. The most constrained window is the one shown — a provider
    /// with several does not make the surface taller, because the limit that will bite
    /// first is the only one worth reading here.
    private var snippet: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                ProviderLogo(provider: surface.selected, size: 10)
                Text(snippetTitle)
                    .font(Tokens.Type_.rowLabel)
                    .foregroundStyle(Tokens.Palette.primaryText)
                    .lineLimit(1)
            }
            Text(snippetDetail)
                .font(Tokens.Type_.rowMeta)
                .foregroundStyle(Tokens.Palette.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Surface.bodyPadding + layout.flare)
        .padding(.vertical, layout.bodyVerticalPadding)
        .frame(width: size.width, height: layout.expandedBodyHeight, alignment: .leading)
    }

    private var snippetTitle: String {
        let name = settings.displayName(for: surface.selected)
        guard let window = status?.headlineWindow else { return name }
        return "\(name) · \(window.label)"
    }

    private var snippetDetail: String {
        guard let status else { return "No data" }
        guard let window = status.headlineWindow,
              let percentage = window.usedPercentage
        else { return status.statusMessage ?? "Unavailable" }

        var parts = ["\(Int(percentage.rounded()))% used"]
        if settings.showResetCountdown,
           let phrase = ResetCalculator.resetPhrase(to: window.resetDate, from: store.now) {
            parts.append(phrase.replacingOccurrences(of: "Resets ", with: "resets "))
        }
        if store.isStale(surface.selected) { parts.append("stale") }
        return parts.joined(separator: " · ")
    }

    private func caption(for status: ProviderStatus?) -> String {
        guard let percentage = status?.headlineWindow?.usedPercentage else { return "—" }
        return "\(Int(percentage.rounded()))%"
    }

    private func select(_ provider: ProviderID) {
        withAnimation(Tokens.Motion.content(reduceMotion: reduceMotion)) {
            surface.selected = provider
            if !surface.isExpanded { surface.isExpanded = true }
        }
    }

    // MARK: Accessibility

    /// "Codex, 73 percent used, warning, resets in 51 minutes."
    private func label(for status: ProviderStatus?) -> String {
        guard let status else { return "No provider" }
        var parts: [String] = [status.displayName]

        if let percentage = status.headlineWindow?.usedPercentage {
            parts.append("\(Int(percentage.rounded())) percent used")
            parts.append(status.state.spokenDescription)
        } else {
            parts.append(status.statusMessage ?? "usage unavailable")
        }

        if let phrase = ResetCalculator.resetPhrase(
            to: status.headlineWindow?.resetDate, from: store.now
        ) {
            parts.append(phrase.replacingOccurrences(of: "Resets", with: "resets"))
        }
        if store.isStale(status.provider) { parts.append("reading is stale") }

        return parts.joined(separator: ", ")
    }
}

private extension UsageState {
    /// Spoken form for accessibility labels.
    var spokenDescription: String {
        switch self {
        case .normal: "normal"
        case .warning: "warning"
        case .critical: "critical"
        case .exhausted: "limit reached"
        case .unavailable: "unavailable"
        case .loading: "checking"
        }
    }
}
