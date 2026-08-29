import SwiftUI
import SideNotchCore

/// A provider's ring: usage arc around a symbol, with the figure beneath.
struct UsageRing: View {
    let status: ProviderStatus
    let isStale: Bool
    let isFocused: Bool
    let showPercentage: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var window: UsageWindow? { status.headlineWindow }
    private var fraction: Double? { window?.usedFraction }
    private var percentage: Double? { window?.usedPercentage }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Tokens.Palette.track, lineWidth: Tokens.Rail.ringLineWidth)

                if let fraction {
                    Circle()
                        .trim(from: 0, to: max(fraction, 0.001))
                        .stroke(
                            Tokens.Palette.ring(forPercentage: percentage),
                            style: StrokeStyle(lineWidth: Tokens.Rail.ringLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))   // start the sweep at 12 o'clock
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: fraction)
                } else if status.state == .loading {
                    Circle()
                        .trim(from: 0, to: 0.18)
                        .stroke(
                            Tokens.Palette.unavailable,
                            style: StrokeStyle(lineWidth: Tokens.Rail.ringLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                Image(systemName: status.provider.symbolName)
                    .font(.system(size: Tokens.Rail.iconSize, weight: .medium))
                    .foregroundStyle(
                        fraction == nil ? Tokens.Palette.unavailable : Tokens.Palette.primaryText
                    )
            }
            .frame(width: Tokens.Rail.ringDiameter, height: Tokens.Rail.ringDiameter)
            .opacity(isStale ? 0.55 : 1)

            if showPercentage {
                Text(percentage.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(Tokens.Type_.percentage)
                    .foregroundStyle(
                        fraction == nil ? Tokens.Palette.unavailable : Tokens.Palette.primaryText
                    )
                    .monospacedDigit()
            }
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
        guard let percentage else {
            return "\(status.displayName), \(status.statusMessage ?? "unavailable")"
        }
        var text = "\(status.displayName), \(Int(percentage.rounded())) percent used"
        if let phrase = ResetCalculator.resetPhrase(to: window?.resetDate) { text += ", \(phrase)" }
        if isStale { text += ", reading is stale" }
        return text
    }
}
