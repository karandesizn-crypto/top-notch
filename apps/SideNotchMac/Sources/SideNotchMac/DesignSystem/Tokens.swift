import SwiftUI
import SideNotchCore

/// Design tokens for the rail and detail card.
///
/// Values are read off the reference concept: a black slab flush to the right screen edge,
/// provider rings stacked vertically, and a detail card that flies out to the left.
enum Tokens {

    // MARK: Geometry

    enum Rail {
        /// Width of the collapsed slab.
        static let width: CGFloat = 74
        /// Vertical space each provider occupies, ring plus percentage label.
        static let itemHeight: CGFloat = 78
        static let ringDiameter: CGFloat = 42
        /// Distance from a slot's top to the ring's top. Pinning this rather than letting
        /// the stack centre itself means the card's tail can be aimed arithmetically.
        static let ringTopInset: CGFloat = 8
        static let ringLineWidth: CGFloat = 3.5
        static let iconSize: CGFloat = 17
        /// Radius of the rounded left corners.
        static let cornerRadius: CGFloat = 22
        /// Radius of the concave fillets where the slab meets the screen edge.
        static let flareRadius: CGFloat = 16
        static let verticalPadding: CGFloat = 14
        /// Gap below the menu bar.
        static let topInset: CGFloat = 8

        /// Height of the hosting panel: enough for the rail, and never less than a full
        /// card needs.
        static func panelHeight(itemCount: Int) -> CGFloat {
            max(geometry(itemCount: itemCount).panelHeight, Tokens.Card.reservedHeight)
        }

        /// Layout arithmetic for the rail, shared with the tests in SideNotchCore.
        static func geometry(itemCount: Int) -> RailGeometry {
            RailGeometry(
                verticalPadding: verticalPadding,
                itemHeight: itemHeight,
                ringTopInset: ringTopInset,
                ringDiameter: ringDiameter,
                itemCount: itemCount
            )
        }
    }

    enum Card {
        static let width: CGFloat = 268
        static let cornerRadius: CGFloat = 18
        static let tailWidth: CGFloat = 11
        static let tailHeight: CGFloat = 20
        static let padding: CGFloat = 14
        static let barHeight: CGFloat = 5
        /// Gap between the card's tail and the rail.
        static let railGap: CGFloat = 6
        /// Vertical room reserved for a fully populated card. The panel is never shorter
        /// than this, so a card beside a one-provider rail is not clipped.
        static let reservedHeight: CGFloat = 320
    }

    // MARK: Color

    enum Palette {
        static let surface = Color(white: 0.04)
        static let cardSurface = Color(white: 0.07)
        static let primaryText = Color.white
        static let secondaryText = Color(white: 0.62)
        static let track = Color(white: 0.24)
        static let unavailable = Color(white: 0.42)

        static let good = Color(red: 0.20, green: 0.82, blue: 0.35)
        static let moderate = Color(red: 0.98, green: 0.83, blue: 0.04)
        static let high = Color(red: 0.98, green: 0.45, blue: 0.09)
        static let severe = Color(red: 0.96, green: 0.26, blue: 0.21)

        /// Ring colour as a continuous ramp over percentage used.
        ///
        /// This is deliberately *not* `UsageHealth`. The health enum drives behaviour —
        /// warnings, the one-shot pulse, notifications — on thresholds the user configures
        /// (80/90 by default). The ring instead reads as a gradient so a glance conveys
        /// roughly how much is left, which is what the reference concept does: 21% green,
        /// 52% yellow, 73% orange. Keeping the two separate means retuning the visual ramp
        /// never silently moves someone's alert thresholds.
        static func ring(forPercentage percentage: Double?) -> Color {
            guard let percentage else { return unavailable }
            switch percentage {
            case ..<35: return good
            case ..<65: return moderate
            case ..<88: return high
            default: return severe
            }
        }

        /// Semantic colour for badges and alert treatments.
        ///
        /// Driven by `UsageState`, which the user's thresholds control — distinct from the
        /// ring ramp above, which is only how a percentage reads at a glance.
        static func semantic(for state: UsageState) -> Color {
            switch state {
            case .normal: good
            case .warning: moderate
            case .critical: high
            case .exhausted: severe
            case .unavailable, .loading: unavailable
            }
        }
    }

    // MARK: Type

    enum Type_ {
        static let percentage = Font.system(size: 13, weight: .semibold, design: .rounded)
        static let cardTitle = Font.system(size: 13, weight: .semibold)
        static let rowLabel = Font.system(size: 11, weight: .medium)
        static let rowMeta = Font.system(size: 10, weight: .regular)
        static let rowValue = Font.system(size: 11, weight: .semibold)
    }

    // MARK: Motion

    enum Motion {
        /// Respects Reduce Motion per MAC_UX.md's interaction principles.
        static func expand(reduceMotion: Bool) -> Animation {
            reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82)
        }
    }
}

extension ProviderID {
    /// SF Symbols stand in for provider marks.
    ///
    /// TECH_STACK.md allows custom provider marks "only where licensing/branding rules
    /// allow", and shipping Anthropic/OpenAI/Cursor logos needs a trademark review first.
    /// These are placeholders that keep the layout honest until that review happens.
    var symbolName: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "circle.hexagongrid"
        case .cursor: "cursorarrow"
        }
    }
}
