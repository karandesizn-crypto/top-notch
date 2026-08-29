import SwiftUI
import Observation
import SideNotchCore
import ProviderKit

/// Presentation state of the surface.
@Observable
@MainActor
final class NotchSurfaceState {
    var isExpanded = false
    /// Set by a click. A pinned surface stays open when the pointer leaves, and is
    /// dismissed by Escape or another click.
    var isPinned = false
    var selected: ProviderID = .codex
}

/// The notch surface: one shape that changes form between a compact status strip and a
/// full usage panel.
///
/// The housing row is always present and always laid out the same way, so expanding never
/// moves the collapsed content — it only reveals more beneath it. That is what makes the
/// transition read as a single surface transforming rather than a popover appearing.
struct NotchRootView: View {
    @Bindable var store: UsageStore
    @Bindable var settings: AppSettings
    @Bindable var surface: NotchSurfaceState
    let layout: NotchSurfaceLayout

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { surface.isExpanded }
    private var providers: [ProviderID] { store.visibleProviders }
    private var status: ProviderStatus? { store.status(for: surface.selected) }
    private var hasSwitcher: Bool { providers.count > 1 }

    private var size: CGSize {
        SurfaceSizing.size(
            layout: layout, expanded: expanded, status: status, providerCount: providers.count
        )
    }

    private var shape: NotchSurfaceShape {
        NotchSurfaceShape(
            flare: layout.flare,
            bottomRadius: expanded
                ? Tokens.Surface.expandedBottomRadius : Tokens.Surface.bottomRadius
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
            housingRow
            if expanded {
                expandedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background {
            shape
                .fill(Tokens.Palette.surface)
                .overlay { shape.stroke(Tokens.Palette.surfaceEdge, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.5), radius: expanded ? 22 : 10, y: expanded ? 10 : 4)
        }
        .clipShape(shape)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: expanded)
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: size.height)
        .onHover { hovering in
            guard !surface.isPinned else { return }
            withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                surface.isExpanded = hovering
            }
        }
        .onTapGesture { togglePinned() }
        .accessibilityElement(children: expanded ? .contain : .ignore)
        .accessibilityLabel(expanded ? "SideNotch usage panel" : label(for: status))
        .accessibilityAddTraits(.isButton)
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

    // MARK: Housing row

    /// The strip either side of the camera housing.
    ///
    /// The middle is a hole, not a spacer with something behind it: nothing can render over
    /// the physical housing, so the layout reserves its exact measured width.
    private var housingRow: some View {
        HStack(spacing: 0) {
            leadingFlank
                .frame(width: layout.flankWidth(expanded: expanded), alignment: .trailing)
            Color.clear
                .frame(width: layout.notchWidth)
            trailingFlank
                .frame(width: layout.flankWidth(expanded: expanded), alignment: .leading)
        }
        .frame(height: layout.rowHeight)
        .padding(.horizontal, layout.flare)
    }

    private var leadingFlank: some View {
        HStack(spacing: 6) {
            Image(systemName: surface.selected.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tokens.Palette.primaryText)
            Text(status?.displayName ?? surface.selected.displayName)
                .font(Tokens.Type_.collapsedProvider)
                .foregroundStyle(Tokens.Palette.primaryText)
                .lineLimit(1)
        }
        .padding(.trailing, Tokens.Surface.horizontalPadding)
    }

    private var trailingFlank: some View {
        HStack(spacing: 7) {
            UsageRing(
                state: status?.state ?? .loading,
                fraction: status?.headlineWindow?.usedFraction,
                symbolName: surface.selected.symbolName,
                diameter: Tokens.Ring.collapsedDiameter,
                lineWidth: Tokens.Ring.collapsedLineWidth,
                glyphSize: Tokens.Ring.collapsedGlyph
            )
            Text(caption(for: status))
                .font(Tokens.Type_.collapsedValue)
                .foregroundStyle(
                    status?.headlineWindow?.usedFraction == nil
                        ? Tokens.Palette.secondaryText : Tokens.Palette.primaryText
                )
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.leading, Tokens.Surface.horizontalPadding)
    }

    // MARK: Expanded body

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasSwitcher {
                providerRow.frame(height: layout.switcherHeight)
            }
            detailCard.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Surface.bodyPadding + layout.flare)
        .padding(.vertical, layout.bodyVerticalPadding)
        .frame(
            height: layout.expandedBodyHeight(
                rowCount: SurfaceSizing.rowCount(for: status), hasSwitcher: hasSwitcher
            )
        )
    }

    /// Every enabled provider at once, in the reference's language: a glyph in a disc, a
    /// usage arc around it, the bold figure beneath. Selecting one swaps the card below
    /// without moving the row.
    private var providerRow: some View {
        HStack(spacing: 0) {
            ForEach(providers, id: \.self) { provider in
                let providerStatus = store.status(for: provider)
                Button {
                    select(provider)
                } label: {
                    UsageRing(
                        state: providerStatus?.state ?? .loading,
                        fraction: providerStatus?.headlineWindow?.usedFraction,
                        symbolName: provider.symbolName,
                        diameter: Tokens.Ring.providerDiameter,
                        lineWidth: Tokens.Ring.providerLineWidth,
                        glyphSize: Tokens.Ring.providerGlyph,
                        caption: caption(for: providerStatus),
                        isEmphasized: provider == surface.selected
                    )
                    .frame(width: Tokens.Ring.providerSlotWidth)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: surface.selected)
                .accessibilityLabel(label(for: providerStatus))
                .accessibilityAddTraits(
                    provider == surface.selected ? [.isSelected, .isButton] : .isButton
                )
            }
            Spacer(minLength: 0)
        }
    }

    /// Title, then one labelled bar per window with its figure and reset time.
    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: surface.selected.symbolName)
                    .font(.system(size: 12, weight: .medium))
                Text("\(status?.displayName ?? surface.selected.displayName) Usage")
                    .font(Tokens.Type_.cardTitle)
                Spacer(minLength: 6)
                if let plan = status?.snapshot?.plan {
                    Text(plan.uppercased())
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.secondaryText)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.09))
                        )
                }
            }
            .foregroundStyle(Tokens.Palette.primaryText)
            .frame(height: layout.cardTitleHeight)

            if let windows = status?.snapshot?.windows, !windows.isEmpty {
                ForEach(windows.prefix(NotchSurfaceLayout.maximumRows)) { window in
                    windowRow(window)
                }
            } else {
                unavailableRow
            }
        }
    }

    private func windowRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(window.label)
                .font(Tokens.Type_.rowLabel)
                .foregroundStyle(Tokens.Palette.primaryText)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tokens.Palette.track)
                    if let fraction = window.usedFraction {
                        // A visible stub at very low percentages, so a bar that exists but
                        // is nearly empty does not look like a missing reading.
                        Capsule()
                            .fill(Tokens.Palette.color(for: window.state))
                            .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 5 : 0))
                    }
                }
            }
            .frame(height: 5)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.usedPercentage.map { "\(Int($0.rounded()))% Used" } ?? "Unavailable")
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.secondaryText)
                    .monospacedDigit()
                Spacer(minLength: 0)
                if settings.showResetCountdown,
                   let phrase = ResetCalculator.resetPhrase(to: window.resetDate, from: store.now) {
                    Text(store.isStale(surface.selected) ? "\(phrase) · stale" : phrase)
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.tertiaryText)
                }
            }
        }
    }

    private var unavailableRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(status?.state == .loading ? "Checking…" : "Unavailable")
                .font(Tokens.Type_.rowLabel)
                .foregroundStyle(Tokens.Palette.primaryText)
            if let message = status?.statusMessage {
                Text(message)
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func caption(for status: ProviderStatus?) -> String {
        guard let percentage = status?.headlineWindow?.usedPercentage else { return "—" }
        return "\(Int(percentage.rounded()))%"
    }

    private func select(_ provider: ProviderID) {
        withAnimation(Tokens.Motion.content(reduceMotion: reduceMotion)) {
            surface.selected = provider
        }
    }

    // MARK: Accessibility

    /// "Codex, 73 percent used, warning, resets in 51 minutes."
    private func label(for status: ProviderStatus?) -> String {
        guard let status else { return "SideNotch, no provider selected" }
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
