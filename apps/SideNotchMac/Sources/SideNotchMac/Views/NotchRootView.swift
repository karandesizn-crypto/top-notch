import SwiftUI
import Observation
import SideNotchCore
import ProviderKit
import NotchKit
import UsageKit

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
    var selected: ProviderType = .codex
}

/// The notch surface: a compact tab hanging below the camera housing that opens into a
/// usage panel.
///
/// The chip row is the whole collapsed state and stays exactly where it is when the tab
/// expands — it doubles as the provider switcher rather than being replaced by a second,
/// larger row. Nothing moves on expand; content is only revealed beneath, which is what
/// makes it read as one surface changing shape.
struct NotchRootView: View {
    @Bindable var manager: UsageManager
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
    @State private var hoverSweepProvider: ProviderType?
    @State private var hoverSweepTask: Task<Void, Never>?

    private var expanded: Bool { surface.isExpanded }
    private var providers: [ProviderType] { manager.visibleProviders }
    private var status: ProviderStatus? { manager.status(for: surface.selected) }

    private var minimized: Bool { surface.isMinimized }

    private var size: CGSize {
        SurfaceSizing.size(
            layout: layout, expanded: expanded, minimized: minimized,
            pinned: surface.isPinned, rows: breakdownWindows.count
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
        .accessibilityLabel("Top Notch usage")
    }

    /// The housing's own row — the camera's own strip, where nothing is drawn because
    /// there are no pixels behind it.
    ///
    /// This is the handle. Pointing at the physical notch tucks the whole surface away to
    /// the mini-notch; pointing at it again brings it back. Expansion belongs to the chips
    /// below, which is what stops the two gestures fighting over the same pixels — and is
    /// why hovering here must never expand: the housing is exactly where the pointer lands
    /// on its way to everything else.
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
                    // The camera housing is the handle: pointing at the physical notch
                    // tucks the whole surface away to the mini-notch, and pointing at it
                    // again brings it back. Expansion belongs to the chips below, which is
                    // what keeps the two gestures from fighting over the same pixels.
                    surface.isMinimized.toggle()
                    if surface.isMinimized { surface.isExpanded = false }
                }
            }
            .accessibilityLabel(minimized ? "Show Top Notch" : "Hide Top Notch")
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
        case provider(ProviderType)
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

    private func chip(_ provider: ProviderType) -> some View {
        let providerStatus = manager.status(for: provider)
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
                Text(surface.isPinned ? breakdownTitle : snippetTitle)
                    .font(Tokens.Type_.rowLabel)
                    .foregroundStyle(Tokens.Palette.primaryText)
                    .lineLimit(1)
            }

            if surface.isPinned {
                // The detail line is deliberately dropped here: it says exactly what the
                // first breakdown row says, and repeating it wastes the panel's height on
                // the one provider that has the most to show.
                breakdown.transition(.opacity)
            } else {
                Text(snippetDetail)
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.Surface.bodyPadding + layout.flare)
        .padding(.vertical, layout.bodyVerticalPadding)
        .frame(
            width: size.width,
            height: layout.expandedBodyHeight(
                pinned: surface.isPinned, rows: breakdownWindows.count
            ),
            alignment: .leading
        )
    }

    /// Every limit the provider reports, one row each, revealed by a click.
    ///
    /// Hovering answers "how close am I?" for the window that bites first. Clicking asks
    /// the fuller question, and a provider with several limits has several answers — a
    /// 41% weekly under a 93% session is a different situation from both being at 93%, and
    /// one line cannot say so.
    ///
    /// A bar rather than a second ring: bars stack and compare down a column, which is the
    /// whole point when there is more than one. Colour comes from the shared
    /// `UsageThresholds` via the same `ProviderDisplayState` the rings use, so a row and
    /// its ring can never disagree.
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(breakdownWindows, id: \.id) { window in
                breakdownRow(window)
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Windows worth drawing: those that actually carry a measurement.
    ///
    /// A window with no figure has no bar to draw and no percentage to state, so it is
    /// omitted rather than shown as an empty track — an empty bar reads as "zero used",
    /// which is a claim we do not have.
    private var breakdownWindows: [UsageWindow] {
        guard let usage = status?.usage else { return [] }
        return Array(
            usage.windows
                .filter { $0.usedFraction != nil }
                .prefix(NotchSurfaceLayout.maximumPinnedRows)
        )
    }

    private func breakdownRow(_ window: UsageWindow) -> some View {
        let fraction = window.usedFraction ?? 0
        let state = ProviderDisplayState(status: .available, level: window.level)
        let tint = Tokens.Palette.color(for: state)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(window.label)
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.secondaryText)
                    .lineLimit(1)
                    .layoutPriority(1)

                if settings.showResetCountdown,
                   let term = ResetCalculator.resetTerm(
                       to: window.resetDate, from: manager.now
                   ) {
                    Text(term)
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 2)

                Text("\(Int((fraction * 100).rounded()))%")
                    .font(Tokens.Type_.chipValue)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Tokens.Palette.track)
                    Capsule()
                        .fill(tint)
                        // Clamped so an overage reading cannot draw past the track.
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .frame(height: layout.pinnedRowHeight, alignment: .top)
    }

    /// Names the provider and its plan, the way the provider states it.
    private var breakdownTitle: String {
        let name = settings.displayName(for: surface.selected)
        guard let plan = status?.usage.plan, !plan.isEmpty else { return name }
        return "\(name) · \(plan.capitalized)"
    }

    /// Extras a click earns that are not limits: credits, tokens today.
    ///
    /// Only what the provider actually reported — an absent field is omitted rather than
    /// shown empty, so this line is short or missing entirely for a sparse provider.
    private var pinnedDetail: String? {
        guard let usage = status?.usage else { return nil }
        var parts: [String] = []

        if let plan = usage.plan { parts.append(plan.uppercased()) }

        // The window the headline is not already showing.
        if let other = usage.windows.first(where: { $0.id != status?.headlineWindow?.id }),
           let percentage = other.usedPercentage {
            parts.append("\(other.label) \(Int(percentage.rounded()))%")
        }

        if let credits = usage.credits?.resetCreditsAvailable, credits > 0 {
            parts.append("\(credits) reset credit\(credits == 1 ? "" : "s")")
        }
        if let raw = usage.metadata["tokensToday"], let tokens = Int64(raw), tokens > 0 {
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
               to: window.resetDate, from: manager.now
           ) {
            parts.append(phrase)
        }
        if manager.isStale(surface.selected) { parts.append("stale") }
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
    private func startHoverSweep(_ provider: ProviderType) {
        guard !reduceMotion, hoverSweepProvider != provider else { return }
        hoverSweepProvider = provider
        hoverSweepTask?.cancel()
        hoverSweepTask = Task {
            try? await Task.sleep(for: UsageManager.minimumVisibleRefresh)
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
    private func activate(_ provider: ProviderType) {
        withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
            surface.selected = provider
            surface.isExpanded = true
            surface.isPinned = true
            surface.isMinimized = false
        }
        Task { await manager.refreshAllStaggered() }
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
            to: status.headlineWindow?.resetDate, from: manager.now
        ) {
            parts.append(phrase.replacingOccurrences(of: "Resets", with: "resets"))
        }
        if manager.isStale(status.provider) { parts.append("reading is stale") }

        return parts.joined(separator: ", ")
    }
}

private extension ProviderDisplayState {
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
