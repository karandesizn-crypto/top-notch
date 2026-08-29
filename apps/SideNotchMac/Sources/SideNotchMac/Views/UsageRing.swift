import SwiftUI
import SideNotchCore

/// Reusable provider ring: a glyph inside a dark disc, ringed by a usage arc, with the
/// percentage beneath.
///
/// Colour comes from `UsageState`, which `UsageStateEvaluator` derives from the user's
/// configured thresholds. The ring holds no threshold logic of its own, so it cannot
/// disagree with the alerts.
struct UsageRing: View {
    let state: UsageState
    /// 0...1, or nil when the provider reports no measurement.
    let fraction: Double?
    let symbolName: String
    var diameter: CGFloat
    var lineWidth: CGFloat
    var glyphSize: CGFloat
    /// Bold figure below the ring. Omitted in the compact form.
    var caption: String?
    var isEmphasized: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinnerAngle: Double = 0

    private var color: Color { Tokens.Palette.color(for: state) }

    var body: some View {
        VStack(spacing: 7) {
            ring
            if let caption {
                Text(caption)
                    .font(Tokens.Type_.ringCaption)
                    .foregroundStyle(
                        state.hasMeasurement
                            ? Tokens.Palette.primaryText : Tokens.Palette.secondaryText
                    )
                    .monospacedDigit()
            }
        }
        .opacity(isEmphasized ? 1 : 0.45)
    }

    private var ring: some View {
        ZStack {
            // The disc the glyph sits on, inset so the arc reads as a separate ring around
            // it rather than a border drawn on it.
            Circle()
                .fill(Tokens.Palette.ringWell)
                .padding(lineWidth / 2 + 1.5)

            Circle()
                .stroke(Tokens.Palette.track, lineWidth: lineWidth)

            switch state {
            case .loading:
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(Tokens.Palette.inert,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(spinnerAngle))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                            spinnerAngle = 360
                        }
                    }
            case .unavailable:
                EmptyView()   // Track only: nothing measured is not zero used.
            default:
                Circle()
                    // A hair of arc at 0%, so an untouched limit still reads as measured.
                    .trim(from: 0, to: max(fraction ?? 0, 0.005))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))   // sweep starts at twelve o'clock
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9),
                        value: fraction
                    )
            }

            Image(systemName: symbolName)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(
                    state.hasMeasurement
                        ? Tokens.Palette.primaryText : Tokens.Palette.secondaryText
                )
        }
        .frame(width: diameter, height: diameter)
    }
}
