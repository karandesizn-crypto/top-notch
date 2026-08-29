import SwiftUI
import SideNotchCore

/// Reusable usage ring.
///
/// Colour comes from `UsageState`, which `UsageStateEvaluator` derives from the user's
/// configured thresholds — the ring cannot disagree with the alerts because it has no
/// threshold logic of its own.
struct UsageRing: View {
    let state: UsageState
    /// 0...1, or nil when the provider reports no measurement.
    let fraction: Double?
    var diameter: CGFloat
    var lineWidth: CGFloat
    /// Drawn inside the ring. Omitted in the compact form.
    var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinnerAngle: Double = 0

    private var color: Color { Tokens.Palette.color(for: state) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Palette.track, lineWidth: lineWidth)

            switch state {
            case .loading:
                loadingArc
            case .unavailable:
                // A dash rather than an empty ring: nothing measured is not zero used.
                Rectangle()
                    .fill(Tokens.Palette.inert)
                    .frame(width: diameter * 0.3, height: max(lineWidth * 0.7, 1.5))
                    .clipShape(Capsule())
            default:
                progressArc
            }

            if let label, state.hasMeasurement {
                Text(label)
                    .font(Tokens.Type_.ringValue)
                    .foregroundStyle(Tokens.Palette.primaryText)
                    .monospacedDigit()
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var progressArc: some View {
        Circle()
            // A hair of arc at 0%, so an untouched limit still reads as "measured" rather
            // than looking like a missing reading.
            .trim(from: 0, to: max(fraction ?? 0, 0.004))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))   // start the sweep at twelve o'clock
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.9), value: fraction)
    }

    private var loadingArc: some View {
        Circle()
            .trim(from: 0, to: 0.22)
            .stroke(Tokens.Palette.inert, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spinnerAngle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    spinnerAngle = 360
                }
            }
    }
}
