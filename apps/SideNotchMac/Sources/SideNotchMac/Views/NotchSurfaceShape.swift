import SwiftUI

/// The silhouette: a surface hanging from the top of the display that reads as the camera
/// housing continuing downward.
///
/// Three details do the work:
///
/// - The very top spans the full width, then flares *inward* through a concave curve. That
///   hollow is what makes the surface look joined to the bezel instead of stuck onto it.
/// - The bottom corners carry a large radius, so the shape stays continuous rather than
///   reading as a rounded rectangle.
/// - Both corner families are quadratic curves with explicit control points. Arcs are
///   ambiguous in SwiftUI's flipped coordinate space, and a `clockwise` flag guessed wrong
///   silently produces a convex bulge.
struct NotchSurfaceShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set { flare = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let flare = min(self.flare, rect.width / 4, rect.height / 2)
        let bodyMinX = rect.minX + flare
        let bodyMaxX = rect.maxX - flare
        let radius = min(bottomRadius, (bodyMaxX - bodyMinX) / 2, rect.height - flare)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Concave flare down into the body on the right.
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX, y: rect.minY + flare),
            control: CGPoint(x: bodyMaxX, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: bodyMaxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX - radius, y: rect.maxY),
            control: CGPoint(x: bodyMaxX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: bodyMinX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX, y: rect.maxY - radius),
            control: CGPoint(x: bodyMinX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: bodyMinX, y: rect.minY + flare))
        // Concave flare back out to the top edge on the left.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: bodyMinX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
