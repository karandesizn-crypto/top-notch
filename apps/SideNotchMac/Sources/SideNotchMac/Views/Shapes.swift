import SwiftUI

/// The rail slab: flush to the right screen edge, with concave fillets top-left and
/// bottom-left so it reads as growing out of the edge rather than floating over it.
///
/// The fillets are the detail that makes the silhouette look native. Each is an arc
/// centred *on* the corner, which bows the boundary into the shape and removes area —
/// concave. Centring the arc inside the shape instead would give an ordinary convex
/// rounded corner.
struct NotchShape: Shape {
    var cornerRadius: CGFloat = Tokens.Rail.cornerRadius
    var flareRadius: CGFloat = Tokens.Rail.flareRadius

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let flare = min(flareRadius, rect.height / 2, rect.width / 2)

        // Each fillet is a quadratic whose control point sits on the interior diagonal, so
        // the curve bows *into* the slab and hollows the corner out. Putting the control on
        // the corner itself would give an ordinary convex rounded corner instead, and arcs
        // are ambiguous here because `clockwise` is interpreted in SwiftUI's flipped space.
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + flare),
            control: CGPoint(x: rect.minX + flare, y: rect.minY + flare)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - flare))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + flare, y: rect.maxY),
            control: CGPoint(x: rect.minX + flare, y: rect.maxY - flare)
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The detail card: a rounded rectangle with a tail on its right edge pointing at the
/// focused provider's ring.
struct CardShape: Shape {
    /// Distance from the card's top to the centre of the tail.
    var tailCenterY: CGFloat
    var cornerRadius: CGFloat = Tokens.Card.cornerRadius
    var tailWidth: CGFloat = Tokens.Card.tailWidth
    var tailHeight: CGFloat = Tokens.Card.tailHeight

    var animatableData: CGFloat {
        get { tailCenterY }
        set { tailCenterY = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bodyMaxX = rect.maxX - tailWidth
        let body = CGRect(
            x: rect.minX, y: rect.minY,
            width: max(0, bodyMaxX - rect.minX), height: rect.height
        )

        var path = Path(roundedRect: body, cornerRadius: cornerRadius)

        // Keep the tail fully on the card body even when the focused ring sits near an end.
        let half = tailHeight / 2
        let center = min(max(tailCenterY, cornerRadius + half), rect.height - cornerRadius - half)
        guard rect.height > (cornerRadius + half) * 2 else { return path }

        var tail = Path()
        tail.move(to: CGPoint(x: bodyMaxX - 1, y: center - half))
        tail.addQuadCurve(
            to: CGPoint(x: bodyMaxX - 1, y: center + half),
            control: CGPoint(x: rect.maxX + 1, y: center)
        )
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}
