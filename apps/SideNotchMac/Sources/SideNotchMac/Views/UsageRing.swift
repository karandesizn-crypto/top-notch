import SwiftUI
import SideNotchCore

/// A provider's ring: percentage arc around a symbol, with the figure beneath.
struct UsageRing: View {
    let snapshot: UsageSnapshot?
    let provider: ProviderID
    let isStale: Bool
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percentage: Double? { snapshot?.percentageUsed }
    private var ringColor: Color { Tokens.Palette.ring(forPercentage: percentage) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Tokens.Palette.track, lineWidth: Tokens.Rail.ringLineWidth)

                if let percentage {
                    Circle()
                        .trim(from: 0, to: min(max(percentage / 100, 0), 1))
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: Tokens.Rail.ringLineWidth, lineCap: .round)
                        )
                        // Start the sweep at 12 o'clock rather than 3.
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: percentage)
                }

                Image(systemName: provider.symbolName)
                    .font(.system(size: Tokens.Rail.iconSize, weight: .medium))
                    .foregroundStyle(
                        percentage == nil ? Tokens.Palette.unavailable : Tokens.Palette.primaryText
                    )
            }
            .frame(width: Tokens.Rail.ringDiameter, height: Tokens.Rail.ringDiameter)
            .opacity(isStale ? 0.55 : 1)

            Text(percentage.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(Tokens.Type_.percentage)
                .foregroundStyle(
                    percentage == nil ? Tokens.Palette.unavailable : Tokens.Palette.primaryText
                )
                .monospacedDigit()
        }
        .padding(.top, Tokens.Rail.ringTopInset)
        .frame(width: Tokens.Rail.width, height: Tokens.Rail.itemHeight, alignment: .top)
        .background {
            if isFocused {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let snapshot else { return "\(provider.displayName), no data" }
        guard let percentage = snapshot.percentageUsed else {
            return "\(provider.displayName), usage unavailable"
        }
        var text = "\(provider.displayName), \(Int(percentage.rounded())) percent used"
        if let phrase = ResetCalculator.resetPhrase(to: snapshot.resetAt) { text += ", \(phrase)" }
        if isStale { text += ", reading is stale" }
        return text
    }
}
