import CoreGraphics

/// Pure functions for computing node positions in a radial tree layout.
/// All positions are in a normalized 800×600 coordinate space.
enum GraphLayoutEngine {
    static let canvasSize = CGSize(width: 800, height: 600)
    static let center = CGPoint(x: 400, y: 300)
    static let topRingRadius: CGFloat = 220
    static let childRadius: CGFloat = 130
    /// Minimum radius used for item rings; auto-grows with count to prevent overlap.
    static let minItemRingRadius: CGFloat = 100
    /// Approximate normalized-space diameter of an item node (used for ring radius calculation).
    private static let itemNodeSize: CGFloat = 52

    /// Positions for N top-level category nodes evenly spaced around a ring.
    static func topLevelPositions(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let angle = (2 * CGFloat.pi / CGFloat(count)) * CGFloat(i) - CGFloat.pi / 2
            return CGPoint(
                x: center.x + topRingRadius * cos(angle),
                y: center.y + topRingRadius * sin(angle)
            )
        }
    }

    /// Positions for child nodes (subcategories or items) fanning out from a parent node,
    /// in the direction away from the canvas center.
    static func childPositions(parentPos: CGPoint, count: Int, radius: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        let outwardAngle = atan2(parentPos.y - center.y, parentPos.x - center.x)
        if count == 1 {
            return [CGPoint(
                x: parentPos.x + radius * cos(outwardAngle),
                y: parentPos.y + radius * sin(outwardAngle)
            )]
        }
        let maxSpread = CGFloat.pi * 0.65
        let spread = min(maxSpread, CGFloat(count - 1) * (CGFloat.pi / 8))
        let step = spread / CGFloat(count - 1)
        let startAngle = outwardAngle - spread / 2
        return (0..<count).map { i in
            let angle = startAngle + CGFloat(i) * step
            return CGPoint(
                x: parentPos.x + radius * cos(angle),
                y: parentPos.y + radius * sin(angle)
            )
        }
    }

    /// Positions for N item nodes evenly arranged in a full circle around the parent.
    /// Radius grows automatically so items don't overlap.
    static func circularItemPositions(parentPos: CGPoint, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let radius = max(minItemRingRadius, CGFloat(count) * itemNodeSize / (2 * .pi))
        return (0..<count).map { i in
            let angle = (2 * CGFloat.pi / CGFloat(count)) * CGFloat(i) - CGFloat.pi / 2
            return CGPoint(
                x: parentPos.x + radius * cos(angle),
                y: parentPos.y + radius * sin(angle)
            )
        }
    }

    /// Scale a normalized position to the real canvas size.
    static func scale(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(
            x: point.x * size.width / canvasSize.width,
            y: point.y * size.height / canvasSize.height
        )
    }
}
