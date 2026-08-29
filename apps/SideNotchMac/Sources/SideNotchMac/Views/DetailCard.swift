import SwiftUI
import SideNotchCore

/// The fly-out card: every window the provider reports, each with a bar, a percentage, and
/// a reset time. Rows are built from the snapshot, so a provider with one window renders
/// one row and a provider with three renders three.
struct DetailCard: View {
    let status: ProviderStatus
    let tailCenterY: CGFloat
    let isStale: Bool
    let showResetCountdown: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let windows = windowsToShow, !windows.isEmpty {
                ForEach(windows) { window in
                    row(for: window)
                }
            } else {
                unavailableBody
            }

            footer
        }
        .padding(Tokens.Card.padding)
        .padding(.trailing, Tokens.Card.tailWidth)
        .frame(width: Tokens.Card.width, alignment: .leading)
        .background {
            CardShape(tailCenterY: tailCenterY)
                .fill(Tokens.Palette.cardSurface)
                .overlay {
                    CardShape(tailCenterY: tailCenterY)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, x: -6, y: 6)
        }
    }

    private var windowsToShow: [UsageWindow]? {
        guard let snapshot = status.snapshot, snapshot.availability.isAvailable else { return nil }
        return snapshot.windows
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: status.provider.symbolName)
                .font(.system(size: 12, weight: .medium))
            Text("\(status.displayName) Usage")
                .font(Tokens.Type_.cardTitle)
            Spacer(minLength: 6)
            if let plan = status.snapshot?.plan {
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
    }

    private var unavailableBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(status.state == .loading ? "Checking…" : "Unavailable")
                .font(Tokens.Type_.rowLabel)
                .foregroundStyle(Tokens.Palette.primaryText)
            if let message = status.statusMessage {
                Text(message)
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let credits = status.snapshot?.credits
        if let credits, credits.unlimited || (credits.resetCreditsAvailable ?? 0) > 0 || credits.balance != nil {
            Divider().overlay(Color.white.opacity(0.08))
            HStack(spacing: 6) {
                Image(systemName: "creditcard")
                    .font(.system(size: 9))
                Text(creditsText(credits))
                    .font(Tokens.Type_.rowMeta)
            }
            .foregroundStyle(Tokens.Palette.secondaryText)
        }
    }

    private func creditsText(_ credits: CreditsInfo) -> String {
        if credits.unlimited { return "Unlimited credits" }
        var parts: [String] = []
        if let balance = credits.balance { parts.append(balance) }
        if let resets = credits.resetCreditsAvailable, resets > 0 {
            parts.append("\(resets) reset credit\(resets == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func row(for window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(Tokens.Type_.rowLabel)
                    .foregroundStyle(Tokens.Palette.primaryText)
                Spacer(minLength: 8)
                if showResetCountdown,
                   let reset = ResetCalculator.resetPhrase(to: window.resetDate, from: now) {
                    Text(reset)
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.secondaryText)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tokens.Palette.track)
                    if let fraction = window.usedFraction {
                        Capsule()
                            .fill(Tokens.Palette.ring(forPercentage: window.usedPercentage))
                            .frame(width: geometry.size.width * fraction)
                    }
                }
            }
            .frame(height: Tokens.Card.barHeight)

            HStack(spacing: 5) {
                Text(window.usedPercentage.map { "\(Int($0.rounded()))% used" } ?? "Unavailable")
                    .font(Tokens.Type_.rowValue)
                    .foregroundStyle(
                        window.usedFraction == nil
                            ? Tokens.Palette.unavailable : Tokens.Palette.primaryText
                    )
                if isStale {
                    // A stale snapshot is marked, never presented as live.
                    Text("· stale")
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.moderate)
                }
            }
        }
        .opacity(isStale ? 0.75 : 1)
    }
}
