import SwiftUI
import SideNotchCore
import UsageKit

/// Reusable provider ring: a glyph inside a dark disc, ringed by a usage arc, with the
/// percentage beneath.
///
/// Colour comes from `UsageState`, which `UsageLevelEvaluator` derives from the user's
/// configured thresholds. The ring holds no threshold logic of its own, so it cannot
/// disagree with the alerts.
struct UsageRing: View {
    let state: ProviderDisplayState
    /// 0...1, or nil when the provider reports no measurement.
    let fraction: Double?
    let provider: ProviderType
    var diameter: CGFloat
    var lineWidth: CGFloat
    var glyphSize: CGFloat
    /// Bold figure below the ring. Omitted in the compact form.
    var caption: String?
    var isEmphasized: Bool = true
    /// Draws a sweep around the ring while a refresh is in flight.
    var isRefreshing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinnerAngle: Double = 0
    @State private var sweepAngle: Double = 0

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
        // A small give on the ring itself, so a click registers as having done something.
        .scaleEffect(isRefreshing && !reduceMotion ? 0.93 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isRefreshing)
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

            ProviderLogo(
                provider: provider,
                size: glyphSize,
                tint: state.hasMeasurement
                    ? Tokens.Palette.primaryText : Tokens.Palette.secondaryText
            )

            if isRefreshing { refreshSweep }
        }
        .frame(width: diameter, height: diameter)
    }
    /// A white arc travelling around a *separate, inner* ring while the provider is being
    /// re-read.
    ///
    /// Inside the usage track rather than on top of it. Overlaying the two meant the sweep
    /// obscured the very figure it was refreshing; giving it its own smaller radius keeps
    /// both legible at once, which is how the reference design handles it.
    ///
    /// One revolution takes 1.3s — measured off the reference rather than guessed. An
    /// earlier 0.85s read as hurried next to it.
    private var refreshSweep: some View {
        Circle()
            .trim(from: 0, to: 0.17)
            .stroke(
                Tokens.Palette.primaryText,
                style: StrokeStyle(lineWidth: max(lineWidth * 0.62, 1), lineCap: .round)
            )
            // Inset to its own radius, clear of the usage arc.
            .padding(lineWidth * 1.7)
            .rotationEffect(.degrees(sweepAngle))
            .onAppear {
                guard !reduceMotion else { return }
                sweepAngle = 0
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    sweepAngle = 360
                }
            }
            // Reduce Motion gets a steady mark instead of a travelling one.
            .opacity(reduceMotion ? 0.5 : 1)
    }
}
