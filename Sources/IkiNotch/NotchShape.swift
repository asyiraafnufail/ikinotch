import SwiftUI

/// Authentic MacBook-style notch silhouette with smooth concave top ears
/// merging into the top bezel and convex rounded bottom corners.
struct NotchShape: Shape {
    var topEarRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var closeTopEdge: Bool = true

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topEarRadius, bottomCornerRadius) }
        set {
            topEarRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = min(topEarRadius, min(w * 0.2, h * 0.45))
        let b = min(bottomCornerRadius, min((w - 2 * r) * 0.45, h - r))
        let k: CGFloat = 0.5522847498

        var path = Path()
        // Top-left outer tip
        path.move(to: CGPoint(x: 0, y: 0))

        // Top-left concave ear: (0, 0) -> (r, r)
        path.addCurve(
            to: CGPoint(x: r, y: r),
            control1: CGPoint(x: r * k, y: 0),
            control2: CGPoint(x: r, y: r * (1 - k))
        )

        // Left vertical edge down to bottom-left corner
        path.addLine(to: CGPoint(x: r, y: h - b))

        // Bottom-left convex rounded corner: (r, h - b) -> (r + b, h)
        path.addCurve(
            to: CGPoint(x: r + b, y: h),
            control1: CGPoint(x: r, y: h - b + b * k),
            control2: CGPoint(x: r + b - b * k, y: h)
        )

        // Bottom horizontal edge
        path.addLine(to: CGPoint(x: w - r - b, y: h))

        // Bottom-right convex rounded corner: (w - r - b, h) -> (w - r, h - b)
        path.addCurve(
            to: CGPoint(x: w - r, y: h - b),
            control1: CGPoint(x: w - r - b + b * k, y: h),
            control2: CGPoint(x: w - r, y: h - b + b * k)
        )

        // Right vertical edge up to top-right ear
        path.addLine(to: CGPoint(x: w - r, y: r))

        // Top-right concave ear: (w - r, r) -> (w, 0)
        path.addCurve(
            to: CGPoint(x: w, y: 0),
            control1: CGPoint(x: w - r, y: r * (1 - k)),
            control2: CGPoint(x: w - r * k, y: 0)
        )

        if closeTopEdge {
            path.closeSubpath()
        }
        return path
    }
}
