import SwiftUI
import SideNotchCore

/// The fly-out card for one provider: every limit window it exposes, each with a bar, a
/// percentage, and a reset time.
struct DetailCard: View {
    let provider: ProviderID
    let snapshots: [UsageSnapshot]
    let tailCenterY: CGFloat
    let staleness: StalenessPolicy
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: provider.symbolName)
                    .font(.system(size: 12, weight: .medium))
                Text("\(provider.displayName) Usage")
                    .font(Tokens.Type_.cardTitle)
            }
            .foregroundStyle(Tokens.Palette.primaryText)

            if snapshots.isEmpty {
                Text("No data")
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.secondaryText)
            } else {
                ForEach(snapshots) { snapshot in
                    row(for: snapshot)
                }
            }
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

    @ViewBuilder
    private func row(for snapshot: UsageSnapshot) -> some View {
        let stale = staleness.isStale(snapshot, now: now)

        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.windowLabel ?? snapshot.scope.rawValue.capitalized)
                    .font(Tokens.Type_.rowLabel)
                    .foregroundStyle(Tokens.Palette.primaryText)
                Spacer(minLength: 8)
                if let reset = resetText(for: snapshot) {
                    Text(reset)
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.secondaryText)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Tokens.Palette.track)
                    if let percentage = snapshot.percentageUsed {
                        Capsule()
                            .fill(Tokens.Palette.ring(forPercentage: percentage))
                            .frame(width: geometry.size.width * min(max(percentage / 100, 0), 1))
                    }
                }
            }
            .frame(height: Tokens.Card.barHeight)

            HStack(spacing: 5) {
                Text(snapshot.percentageUsed.map { "\(Int($0.rounded()))% Used" } ?? "Unavailable")
                    .font(Tokens.Type_.rowValue)
                    .foregroundStyle(
                        snapshot.percentageUsed == nil
                            ? Tokens.Palette.unavailable : Tokens.Palette.primaryText
                    )
                if stale {
                    // DOMAIN_MODEL.md: a stale snapshot is marked, never shown as live.
                    Text("· stale")
                        .font(Tokens.Type_.rowMeta)
                        .foregroundStyle(Tokens.Palette.moderate)
                }
            }

            if let detail = snapshot.detail {
                Text(detail)
                    .font(Tokens.Type_.rowMeta)
                    .foregroundStyle(Tokens.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(stale ? 0.75 : 1)
    }

    /// "Resets in 51 min" for anything within a day, otherwise a weekday and time —
    /// a countdown of "6d 3h" is less useful than "Resets Thu 12:00 AM".
    private func resetText(for snapshot: UsageSnapshot) -> String? {
        guard let resetAt = snapshot.resetAt else { return nil }
        let interval = resetAt.timeIntervalSince(now)
        guard interval > 0 else { return "Resetting now" }

        if interval < 86400 {
            guard let countdown = ResetCalculator.countdown(to: resetAt, from: now) else { return nil }
            return "Resets in \(countdown)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = interval < 7 * 86400 ? "EEE h:mm a" : "MMM d, h:mm a"
        return "Resets \(formatter.string(from: resetAt))"
    }
}
