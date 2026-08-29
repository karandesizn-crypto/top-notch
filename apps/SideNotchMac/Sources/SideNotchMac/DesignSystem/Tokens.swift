import SwiftUI
import SideNotchCore

/// Design tokens for the notch surface.
///
/// The tab hangs below the camera housing rather than straddling it, so its size is set
/// here rather than borrowed from the hardware. Only the *anchor* comes from the display.
enum Tokens {

    enum Surface {
        /// Outward flare where the tab meets the chrome above it.
        static let flare: CGFloat = 10
        static let collapsedRadius: CGFloat = 14
        static let expandedRadius: CGFloat = 18
        /// Radius of the neck where the housing meets the panel.
        static let shoulderRadius: CGFloat = 10

        static let chipSpacing: CGFloat = 0
        static let bodyPadding: CGFloat = 14
    }

    enum Ring {
        /// The provider rings, sized to sit inside the menu bar row beside the camera.
        static let chipDiameter: CGFloat = 21
        static let chipLineWidth: CGFloat = 2.2
        static let chipGlyph: CGFloat = 11
        /// Smallest a chip may be before the panel outgrows the housing, with and without
        /// a figure beside the ring.
        static let minimumChipWidth: CGFloat = 34
        static let minimumChipWidthWithFigure: CGFloat = 58
    }

    enum Palette {
        /// Pure black, matching the camera housing exactly.
        ///
        /// An earlier near-black was chosen so the panel would separate from the housing by
        /// a hair. On real hardware that hair is a visible seam: the housing is true black,
        /// and anything lighter beside it reads as a separate object stuck underneath.
        static let surface = Color.black
        static let primaryText = Color.white
        static let secondaryText = Color(white: 0.60)
        static let tertiaryText = Color(white: 0.42)
        static let track = Color(white: 0.20)
        /// The disc a provider glyph sits on, inside its ring.
        static let ringWell = Color(white: 0.15)

        static let normal = Color(red: 0.20, green: 0.82, blue: 0.35)
        static let warning = Color(red: 0.98, green: 0.79, blue: 0.10)
        static let critical = Color(red: 0.99, green: 0.42, blue: 0.10)
        static let exhausted = Color(red: 0.97, green: 0.27, blue: 0.24)
        static let inert = Color(white: 0.38)

        /// The single source of colour for usage state.
        ///
        /// Driven by `ProviderDisplayState`, which folds the domain's status and level
        /// into the one thing the ring needs: which treatment to draw. There is
        /// deliberately no second ramp — two systems would let the ring disagree with the
        /// alerts.
        static func color(for state: ProviderDisplayState) -> Color {
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
        static let chipValue = Font.system(size: 10, weight: .semibold, design: .rounded)
        static let ringCaption = Font.system(size: 11, weight: .bold, design: .rounded)
        static let cardTitle = Font.system(size: 12, weight: .semibold)
        static let rowLabel = Font.system(size: 10.5, weight: .medium)
        static let rowMeta = Font.system(size: 9.5, weight: .regular)
    }

    enum Motion {
        /// One spring for the whole surface, so shape, width, height, and content move
        /// together and read as a single object changing form. Damping is high on purpose:
        /// a system surface transforming, not a widget bouncing.
        static func surface(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.88)
        }

        static func content(reduceMotion: Bool) -> Animation {
            reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.26, dampingFraction: 0.9)
        }
    }
}

extension ProviderType {
    /// SF Symbols stand in for provider marks: shipping the real Anthropic, OpenAI, and
    /// Cursor logos needs a trademark review first. User-added tools get a neutral glyph.
    var symbolName: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "circle.hexagongrid"
        case .cursor: "cursorarrow"
        default: "square.stack.3d.up"
        }
    }
}
