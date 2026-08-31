import SwiftUI

/// One silhouette spanning the camera housing and the panel beneath it.
///
/// The top section is the housing's own width and sits inside the notch row, where the
/// display has no pixels — invisible, but it is what makes the shape continuous. At the
/// housing's lower edge the outline necks in to the panel's width through a concave curve,
/// mirroring the hardware's own shoulders, so the panel reads as the notch continuing
/// downward instead of a separate pill hanging under it.
///
/// Drawing the panel as its own rounded rectangle is what made it look detached: it had its
/// own top corners meeting the housing's bottom corners, and the two never lined up.
struct NotchSurfaceShape: Shape {
    /// Width of the physical housing.
    var notchWidth: CGFloat
    /// Height of the housing row.
    var notchHeight: CGFloat
    /// Width of the panel below the housing.
    var bodyWidth: CGFloat
    /// Radius of the panel's bottom corners.
    var bottomRadius: CGFloat
    /// Radius of the neck where the housing meets the panel.
    var shoulderRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(bodyWidth, bottomRadius), shoulderRadius) }
        set {
            bodyWidth = newValue.first.first
            bottomRadius = newValue.first.second
            shoulderRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let centerX = rect.midX
        let notchHalf = notchWidth / 2
        let bodyHalf = max(bodyWidth, 1) / 2
        let bodyBottom = rect.maxY
        let bodyHeight = max(bodyBottom - notchHeight, 0)

        let shoulder = min(shoulderRadius, bodyHeight / 2)
        let radius = min(bottomRadius, bodyHalf, max(bodyHeight - shoulder, 0))

        // How far the panel has to neck in from the housing on each side.
        //
        // Zero whenever the panel is as wide as the housing — which is every state except
        // the tucked-away one, because `collapsedSize` is already the notch's width. So
        // this shoulder is only really drawn when the surface shrinks to the mini-notch,
        // which is precisely where the old single-curve version showed a hard corner.
        let neck = notchHalf - bodyHalf

        // The two turns are clamped separately, because they live in different places.
        //
        // The convex one happens up inside the housing row, which is 32pt tall, so it can
        // take the full radius. The concave one falls away into the panel and cannot be
        // deeper than the panel is tall. Clamping both by the panel — as a single shared
        // radius does — squeezes the outer corner to 2.5pt when the panel is the 5pt
        // mini-notch, and a 2.5pt round-over on a 185pt edge still reads as a corner.
        // Both derive from `shoulderRadius` rather than `shoulder`, which is already capped
        // at half the panel's height for the bottom-corner maths and would re-impose the
        // very clamp this split exists to avoid.
        let turnOuter = max(min(shoulderRadius, neck / 2, notchHeight / 2), 0)
        let turnInner = max(min(shoulderRadius, neck / 2, bodyHeight), 0)

        var path = Path()

        // Left edge of the housing, from the top of the display down toward its lower edge.
        path.move(to: CGPoint(x: centerX - notchHalf, y: rect.minY))

        if neck > 0.5 {
            // Two quarter-turns rather than one curve, because the corner has to change
            // direction twice and a single quad can only do it once.
            //
            // The old version ran the vertical wall straight into a curve whose control
            // point sat level with the corner: the wall arrived pointing down, the curve
            // left pointing sideways, and nothing reconciled the two. That tangent
            // discontinuity is the sharp corner — a ~90° kink exactly where the surface
            // emerges from under the physical notch.
            //
            // A real notch never does that. Its wall eases into the underside through a
            // convex round-over, runs flat, then falls away through a concave fillet. Both
            // joins are tangent-continuous, so the outline turns rather than folds.
            path.addLine(to: CGPoint(x: centerX - notchHalf, y: notchHeight - turnOuter))
            // Convex: heading down, leaving horizontal.
            path.addQuadCurve(
                to: CGPoint(x: centerX - notchHalf + turnOuter, y: notchHeight),
                control: CGPoint(x: centerX - notchHalf, y: notchHeight)
            )
            // The housing's underside.
            path.addLine(to: CGPoint(x: centerX - bodyHalf - turnInner, y: notchHeight))
            // Concave: heading horizontal, leaving down.
            path.addQuadCurve(
                to: CGPoint(x: centerX - bodyHalf, y: notchHeight + turnInner),
                control: CGPoint(x: centerX - bodyHalf, y: notchHeight)
            )
        } else {
            // Panel the same width as the housing, or a hair wider where the chip row needs
            // an extra point or two. The wall stays vertical to the housing's lower edge and
            // the original single curve takes it from there — a two-turn construction here
            // would slant the wall to meet a body 0.5pt wider, which is a visible skew for
            // no gain.
            path.addLine(to: CGPoint(x: centerX - notchHalf, y: notchHeight))
            path.addQuadCurve(
                to: CGPoint(x: centerX - bodyHalf, y: notchHeight + shoulder),
                control: CGPoint(x: centerX - bodyHalf, y: notchHeight)
            )
        }

        path.addLine(to: CGPoint(x: centerX - bodyHalf, y: bodyBottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: centerX - bodyHalf + radius, y: bodyBottom),
            control: CGPoint(x: centerX - bodyHalf, y: bodyBottom)
        )

        path.addLine(to: CGPoint(x: centerX + bodyHalf - radius, y: bodyBottom))
        path.addQuadCurve(
            to: CGPoint(x: centerX + bodyHalf, y: bodyBottom - radius),
            control: CGPoint(x: centerX + bodyHalf, y: bodyBottom)
        )

        if neck > 0.5 {
            // The same two turns mirrored, walked upward: concave away from the panel, flat
            // along the housing's underside, then convex back into the vertical wall.
            path.addLine(to: CGPoint(x: centerX + bodyHalf, y: notchHeight + turnInner))
            path.addQuadCurve(
                to: CGPoint(x: centerX + bodyHalf + turnInner, y: notchHeight),
                control: CGPoint(x: centerX + bodyHalf, y: notchHeight)
            )
            path.addLine(to: CGPoint(x: centerX + notchHalf - turnOuter, y: notchHeight))
            path.addQuadCurve(
                to: CGPoint(x: centerX + notchHalf, y: notchHeight - turnOuter),
                control: CGPoint(x: centerX + notchHalf, y: notchHeight)
            )
        } else {
            path.addLine(to: CGPoint(x: centerX + bodyHalf, y: notchHeight + shoulder))
            path.addQuadCurve(
                to: CGPoint(x: centerX + notchHalf, y: notchHeight),
                control: CGPoint(x: centerX + bodyHalf, y: notchHeight)
            )
        }

        path.addLine(to: CGPoint(x: centerX + notchHalf, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
