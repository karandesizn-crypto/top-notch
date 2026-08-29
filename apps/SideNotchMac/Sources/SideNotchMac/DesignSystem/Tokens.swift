import SwiftUI
import SideNotchCore

/// Design tokens for the notch surface.
///
/// Sizes that depend on the hardware — the housing's width and height — are never tokens.
/// They come from `NotchMetrics` at runtime, so the surface fits whatever display it is on.
enum Tokens {

    enum Surface {
        /// Content width either side of the housing when collapsed.
        static let collapsedFlank: CGFloat = 104
        /// Content width either side of the housing when expanded.
        static let expandedFlank: CGFloat = 150

        /// Width of the outward flare where the surface meets the top of the display.
        static let flare: CGFloat = 14
        /// Radius of the two bottom corners. Large, so the silhouette reads as one
        /// continuous shape rather than a rounded rectangle.
        static let bottomRadius: CGFloat = 22
        static let expandedBottomRadius: CGFloat = 30

        static let horizontalPadding: CGFloat = 14
        static let bodyPadding: CGFloat = 18

        /// Minimum height, for displays with no housing to borrow a height from.
        static let minimumRowHeight: CGFloat = 26
    }

    enum Ring {
        static let collapsedDiameter: CGFloat = 17
        static let collapsedLineWidth: CGFloat = 2.5
        static let expandedDiameter: CGFloat = 54
        static let expandedLineWidth: CGFloat = 5
    }

    enum Palette {
        /// Near-black rather than pure black, so the surface separates from the housing by
        /// a hair in bright rooms while still reading as one object.
        static let surface = Color(red: 0.043, green: 0.043, blue: 0.047)
        static let surfaceEdge = Color.white.opacity(0.07)
        static let primaryText = Color.white
        static let secondaryText = Color(white: 0.60)
        static let tertiaryText = Color(white: 0.42)
        static let track = Color(white: 0.20)

        static let normal = Color(red: 0.20, green: 0.82, blue: 0.35)
        static let warning = Color(red: 0.98, green: 0.79, blue: 0.10)
        static let critical = Color(red: 0.99, green: 0.45, blue: 0.10)
        static let exhausted = Color(red: 0.97, green: 0.27, blue: 0.24)
        static let inert = Color(white: 0.38)

        /// The single source of colour for usage state.
        ///
        /// Driven entirely by `UsageState`, which `UsageStateEvaluator` derives from the
        /// user's configured thresholds. There is deliberately no second colour ramp: two
        /// systems would let the ring disagree with the alerts.
        static func color(for state: UsageState) -> Color {
            switch state {
            case .normal: normal
            case .warning: warning
            case .critical: critical
            case .exhausted: exhausted
            case .unavailable, .loading: inert
            }
        }
    }

    enum Type_ {
        static let collapsedProvider = Font.system(size: 12, weight: .medium)
        static let collapsedValue = Font.system(size: 12, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 15, weight: .semibold)
        static let ringValue = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let rowLabel = Font.system(size: 11, weight: .medium)
        static let rowMeta = Font.system(size: 10.5, weight: .regular)
        static let switcher = Font.system(size: 10, weight: .medium)
    }

    enum Motion {
        /// One spring for the whole surface, so the shape, width, height, and content all
        /// move together and read as a single object changing form.
        ///
        /// Damping is high on purpose: the brief calls for a system surface transforming,
        /// not a bouncing widget.
        static func surface(reduceMotion: Bool) -> Animation {
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.38, dampingFraction: 0.86)
        }

        static func content(reduceMotion: Bool) -> Animation {
            reduceMotion
                ? .easeOut(duration: 0.1)
                : .spring(response: 0.30, dampingFraction: 0.90)
        }
    }
}

extension ProviderID {
    /// SF Symbols stand in for provider marks: shipping the real Anthropic, OpenAI, and
    /// Cursor logos needs a trademark review first.
    var symbolName: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "circle.hexagongrid"
        case .cursor: "cursorarrow"
        case .chatgpt: "bubble.left.and.bubble.right"
        }
    }
}
