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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { surface.isExpanded }
    private var providers: [ProviderID] { store.visibleProviders }
    private var status: ProviderStatus? { store.status(for: surface.selected) }

    private var size: CGSize {
        SurfaceSizing.size(layout: layout, expanded: expanded, status: status)
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
            if expanded {
                detailCard
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
        .animation(Tokens.Motion.surface(reduceMotion: reduceMotion), value: size.height)
        .onHover { hovering in
            guard !surface.isPinned else { return }
            withAnimation(Tokens.Motion.surface(reduceMotion: reduceMotion)) {
                surface.isExpanded = hovering
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
    private var chipRow: some View {
        HStack(spacing: Tokens.Surface.chipSpacing) {
            ForEach(providers) { provider in
                chip(provider)
            }
        }
        .padding(.horizontal, layout.horizontalPadding + layout.flare)
        .frame(height: layout.collapsedHeight)
    }

    private func chip(_ provider: ProviderID) -> some View {
        let providerStatus = store.status(for: provider)
        let isSelected = expanded && provider == surface.selected

        return Button {
            select(provider)
        } label: {
            HStack(spacing: 5) {
                UsageRing(
                    state: providerStatus?.state ?? .loading,
                    fraction: providerStatus?.headlineWindow?.usedFraction,
                    symbolName: provider.symbolName,
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
            .frame(width: layout.chipWidth, height: layout.collapsedHeight - 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: surface.selected)
        .accessibilityLabel(label(for: providerStatus))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Expanded detail

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: layout.contentRowSpacing) {
            HStack(spacing: 6) {
                Image(systemName: surface.selected.symbolName)
                    .font(.system(size: 11, weight: .medium))
                Text("\(settings.displayName(for: surface.selected)) Usage")
                    .font(Tokens.Type_.cardTitle)
                Spacer(minLength: 6)
                if let plan = status?.snapshot?.plan {
                    Text(plan.uppercased())
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.secondaryText)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Surface.bodyPadding + layout.flare)
        .padding(.vertical, layout.bodyVerticalPadding)
        .frame(
            width: size.width,
            height: layout.expandedBodyHeight(rowCount: SurfaceSizing.rowCount(for: status)),
            alignment: .top
        )
    }

    private func windowRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.label)
                    .font(Tokens.Type_.rowLabel)
                    .foregroundStyle(Tokens.Palette.primaryText)
                Spacer(minLength: 0)
                if settings.showResetCountdown,
                   let phrase = ResetCalculator.resetPhrase(to: window.resetDate, from: store.now) {
                    Text(store.isStale(surface.selected) ? "\(phrase) · stale" : phrase)
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.tertiaryText)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tokens.Palette.track)
                    if let fraction = window.usedFraction {
                        // A visible stub at very low percentages, so a bar that exists but
                        // is nearly empty does not look like a missing reading.
                        Capsule()
                            .fill(Tokens.Palette.color(for: window.state))
                            .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 4 : 0))
                    }
                }
            }
            .frame(height: 4)

            Text(window.usedPercentage.map { "\(Int($0.rounded()))% used" } ?? "Unavailable")
                .font(Tokens.Type_.rowMeta)
                .foregroundStyle(Tokens.Palette.secondaryText)
                .monospacedDigit()
        }
        .frame(height: layout.contentRowHeight, alignment: .top)
    }

    private var unavailableRow: some View {
        VStack(alignment: .leading, spacing: 2) {
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
