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

    /// The one ring currently sweeping because the pointer is on it.
    ///
    /// Only that ring animates — hovering is a pointer-by-pointer gesture, and sweeping all
    /// of them would say something the hover did not mean. A click is what animates the
    /// whole row, because a click really does re-read all of them.
    ///
    /// The sweep is animation only. Hovering is passive and constant, and performing a real
    /// refresh on it would hammer the providers' local interfaces for no benefit.
    @State private var hoverSweepProvider: ProviderID?
    @State private var hoverSweepTask: Task<Void, Never>?

    private var expanded: Bool { surface.isExpanded }
    private var providers: [ProviderID] { store.visibleProviders }
    private var status: ProviderStatus? { store.status(for: surface.selected) }

    private var minimized: Bool { surface.isMinimized }

    private var size: CGSize {
        SurfaceSizing.size(
            layout: layout, expanded: expanded, minimized: minimized, pinned: surface.isPinned
        )
    }

    /// Size of the panel below the housing, in the current state.
    private var bodySize: CGSize { size }

    /// The full silhouette: housing section plus the panel beneath it.
    private var shape: NotchSurfaceShape {
        NotchSurfaceShape(
            notchWidth: layout.notchWidth,
            notchHeight: layout.surfaceTopInset,
            bodyWidth: bodySize.width,
            bottomRadius: expanded ? Tokens.Surface.expandedRadius : Tokens.Surface.collapsedRadius,
            shoulderRadius: Tokens.Surface.shoulderRadius
        )
    }

    /// Width the silhouette needs: the wider of the housing and the panel.
    private var surfaceWidth: CGFloat {
        max(layout.notchWidth, bodySize.width)
    }

    var body: some View {
        VStack(spacing: 0) {
            surfaceBody
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The whole surface: one shape spanning the housing and the panel, with the content
    /// laid out below the housing row.
    private var surfaceBody: some View {
        ZStack(alignment: .top) {
            shape
                .fill(Tokens.Palette.surface)
                .shadow(color: .black.opacity(0.4), radius: expanded ? 12 : 5, y: expanded ? 5 : 2)

            VStack(spacing: 0) {
                housingHoverRegion
                if !minimized {
                    chipRow
                    if expanded {
                        snippet.transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .frame(
            width: surfaceWidth,
            height: layout.surfaceTopInset + bodySize.height,
            alignment: .top
        )
        .clipShape(shape)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: expanded)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: minimized)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: bodySize.width)
        .onHover { hovering in
            // Leaving the surface collapses the snippet; a chip has to be hovered to open it.
            guard !surface.isPinned, !hovering else { return }
            withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                surface.isExpanded = false
            }
        }
        .onTapGesture { togglePinned() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SideNotch usage")
    }

    /// The housing's own row. Nothing visible is drawn here — the camera has no pixels
    /// behind it — but hovering it tucks the chips away, and hovering it again brings them
    /// back.
    ///
    /// Toggling on entry rather than continuously means one pass of the pointer fires it
    /// once instead of flickering while the pointer rests there.
    private var housingHoverRegion: some View {
        Color.clear
            .frame(height: layout.surfaceTopInset)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard hovering, !surface.isPinned else { return }
                withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                    surface.isMinimized.toggle()
                    if surface.isMinimized { surface.isExpanded = false }
                }
            }
            .accessibilityLabel(minimized ? "Show SideNotch" : "Hide SideNotch")
            .accessibilityAddTraits(.isButton)
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

    /// One group of chips, centred beneath the camera.
    private var chipRow: some View {
        HStack(spacing: 0) {
            ForEach(rowItems, id: \.self) { item($0) }
        }
        .padding(.horizontal, layout.horizontalPadding + layout.flare)
        .frame(height: layout.chipRowHeight)
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Tokens.Palette.secondaryText)
                .frame(width: Tokens.Ring.chipDiameter, height: Tokens.Ring.chipDiameter)
                .background { Circle().fill(Color.white.opacity(0.08)) }
                .frame(width: layout.chipWidth, height: layout.chipRowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a tool")
    }

    private func chip(_ provider: ProviderID) -> some View {
        let providerStatus = store.status(for: provider)
        let isSelected = expanded && provider == surface.selected

        return Button {
            activate(provider)
        } label: {
            HStack(spacing: 4) {
                UsageRing(
                    state: providerStatus?.state ?? .loading,
                    fraction: providerStatus?.headlineWindow?.usedFraction,
                    provider: provider,
                    diameter: Tokens.Ring.chipDiameter,
                    lineWidth: Tokens.Ring.chipLineWidth,
                    glyphSize: Tokens.Ring.chipGlyph,
                    // A real read, or this ring's hover sweep — drawn identically.
                    isRefreshing: (providerStatus?.isRefreshing ?? false)
                        || hoverSweepProvider == provider
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
            .frame(width: layout.chipWidth, height: layout.chipRowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .padding(.vertical, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: surface.selected)
        // Hovering a chip opens the snippet, decides what it shows, and sweeps every ring.
        .onHover { hovering in
            guard hovering, !surface.isPinned, !surface.isMinimized else { return }
            withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                surface.selected = provider
                surface.isExpanded = true
            }
            startHoverSweep(provider)
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

            if surface.isPinned, let extra = pinnedDetail {
                Text(extra)
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.tertiaryText)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Surface.bodyPadding + layout.flare)
        .padding(.vertical, layout.bodyVerticalPadding)
        .frame(
            width: size.width,
            height: layout.expandedBodyHeight(pinned: surface.isPinned),
            alignment: .leading
        )
    }

    /// The extra line a click earns: plan, the other window, credits, tokens today.
    ///
    /// Only what the provider actually reported — an absent field is omitted rather than
    /// shown empty, so this line is short or missing entirely for a sparse provider.
    private var pinnedDetail: String? {
        guard let snapshot = status?.snapshot else { return nil }
        var parts: [String] = []

        if let plan = snapshot.plan { parts.append(plan.uppercased()) }

        // The window the headline is not already showing.
        if let other = snapshot.windows.first(where: { $0.id != status?.headlineWindow?.id }),
           let percentage = other.usedPercentage {
            parts.append("\(other.label) \(Int(percentage.rounded()))%")
        }

        if let credits = snapshot.credits?.resetCreditsAvailable, credits > 0 {
            parts.append("\(credits) reset credit\(credits == 1 ? "" : "s")")
        }
        if let raw = snapshot.metadata["tokensToday"], let tokens = Int64(raw), tokens > 0 {
            parts.append(Self.formatTokens(tokens) + " today")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func formatTokens(_ tokens: Int64) -> String {
        switch tokens {
        case 1_000_000...: String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...: "\(tokens / 1_000)K"
        default: "\(tokens)"
        }
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
           let phrase = ResetCalculator.compactResetPhrase(
               to: window.resetDate, from: store.now
           ) {
            parts.append(phrase)
        }
        if store.isStale(surface.selected) { parts.append("stale") }
        return parts.joined(separator: " · ")
    }

    private func caption(for status: ProviderStatus?) -> String {
        guard let percentage = status?.headlineWindow?.usedPercentage else { return "—" }
        return "\(Int(percentage.rounded()))%"
    }

    /// Sweeps one ring for a turn.
    ///
    /// Re-entering the same ring while it is already sweeping is ignored, so resting the
    /// pointer does not restart it. Moving to a different ring hands the sweep over.
    private func startHoverSweep(_ provider: ProviderID) {
        guard !reduceMotion, hoverSweepProvider != provider else { return }
        hoverSweepProvider = provider
        hoverSweepTask?.cancel()
        hoverSweepTask = Task {
            try? await Task.sleep(for: UsageStore.minimumVisibleRefresh)
            guard !Task.isCancelled else { return }
            if hoverSweepProvider == provider { hoverSweepProvider = nil }
        }
    }

    /// A click selects the provider, pins its snippet open, and re-reads **every** tool.
    ///
    /// Re-reading on click is the point: a deliberate click usually means "is this still
    /// true?", and the sweep answers that the question was heard even when the figures come
    /// back unchanged. All the rings animate rather than only the one clicked, staggered so
    /// it reads as a cascade rather than a glitch — one click refreshes the lot.
    private func activate(_ provider: ProviderID) {
        withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
            surface.selected = provider
            surface.isExpanded = true
            surface.isPinned = true
            surface.isMinimized = false
        }
        Task { await store.refreshAllStaggered() }
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
