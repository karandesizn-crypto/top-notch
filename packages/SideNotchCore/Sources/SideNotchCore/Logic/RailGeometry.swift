import Foundation
import CoreGraphics

/// Layout arithmetic for the rail and its fly-out card.
///
/// This lives in Core rather than in the view because it is pure arithmetic that is easy
/// to get subtly wrong — a tail that points at empty space still compiles and still
/// renders. Keeping it here makes it testable without a running app.
public struct RailGeometry: Sendable {
    public let verticalPadding: CGFloat
    public let itemHeight: CGFloat
    public let ringTopInset: CGFloat
    public let ringDiameter: CGFloat
    public let itemCount: Int

    public init(
        verticalPadding: CGFloat,
        itemHeight: CGFloat,
        ringTopInset: CGFloat,
        ringDiameter: CGFloat,
        itemCount: Int
    ) {
        self.verticalPadding = verticalPadding
        self.itemHeight = itemHeight
        self.ringTopInset = ringTopInset
        self.ringDiameter = ringDiameter
        self.itemCount = itemCount
    }

    public var panelHeight: CGFloat {
        verticalPadding * 2 + itemHeight * CGFloat(itemCount)
    }

    /// Centre of the ring at `index`, measured from the panel's top edge.
    public func ringCenterY(index: Int) -> CGFloat {
        verticalPadding + CGFloat(index) * itemHeight + ringTopInset + ringDiameter / 2
    }

    /// How far down the panel the card sits.
    ///
    /// The card centres on the ring it describes, then is clamped inside the panel. A card
    /// with one row is much shorter than one with three, so a fixed top would leave the
    /// tail unable to reach the lower rings.
    /// - Parameter containerHeight: height of the panel the card is clamped inside. This
    ///   is not always `panelHeight`: with a single provider the rail is short but the
    ///   panel is kept tall enough for a full card, and clamping to the rail's height
    ///   would slice the card off.
    public func cardOffset(
        index: Int, cardHeight: CGFloat, containerHeight: CGFloat? = nil
    ) -> CGFloat {
        guard cardHeight > 0 else { return 0 }
        let container = containerHeight ?? panelHeight
        let ideal = ringCenterY(index: index) - cardHeight / 2
        return min(max(ideal, 0), max(0, container - cardHeight))
    }

    /// Tail position within the card's own coordinate space.
    public func tailCenterY(
        index: Int, cardHeight: CGFloat, containerHeight: CGFloat? = nil
    ) -> CGFloat {
        ringCenterY(index: index)
            - cardOffset(index: index, cardHeight: cardHeight, containerHeight: containerHeight)
    }
}
