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

        var path = Path()

        // Left edge of the housing, from the top of the display down to its lower edge.
        path.move(to: CGPoint(x: centerX - notchHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: centerX - notchHalf, y: notchHeight))

        // Neck in (or out) to the panel's width. The control point sits at the corner the
        // two edges would otherwise meet in, which is what makes the join read as one
        // continuous outline rather than two shapes touching.
        path.addQuadCurve(
            to: CGPoint(x: centerX - bodyHalf, y: notchHeight + shoulder),
            control: CGPoint(x: centerX - bodyHalf, y: notchHeight)
        )

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

        path.addLine(to: CGPoint(x: centerX + bodyHalf, y: notchHeight + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: centerX + notchHalf, y: notchHeight),
            control: CGPoint(x: centerX + bodyHalf, y: notchHeight)
        )

        path.addLine(to: CGPoint(x: centerX + notchHalf, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
