import CoreGraphics
import Foundation

/// Pure geometry for the shape tool (no drawing state), kept separate so it can be unit-tested.
nonisolated enum ShapeGeometry {
    /// Bounding box of a drag from `start` to `end`.
    /// - `square`: forces equal width and height (the larger drag distance wins).
    /// - `fromCenter`: `start` is the centre instead of a corner.
    static func box(start: CGPoint, end: CGPoint, square: Bool, fromCenter: Bool) -> CGRect {
        var dx = end.x - start.x, dy = end.y - start.y
        if square {
            let m = max(abs(dx), abs(dy))
            dx = dx < 0 ? -m : m
            dy = dy < 0 ? -m : m
        }
        if fromCenter {
            return CGRect(x: start.x - abs(dx), y: start.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
        }
        return CGRect(x: min(start.x, start.x + dx), y: min(start.y, start.y + dy), width: abs(dx), height: abs(dy))
    }

    /// Line endpoints. `constrain` snaps the angle to multiples of 45° keeping the length;
    /// `fromCenter` mirrors the start around... i.e. the drag start is the midpoint.
    static func line(start: CGPoint, end: CGPoint, constrain: Bool, fromCenter: Bool) -> (CGPoint, CGPoint) {
        var e = end
        if constrain {
            let dx = end.x - start.x, dy = end.y - start.y
            let len = hypot(dx, dy)
            let step = CGFloat.pi / 4
            let a = (atan2(dy, dx) / step).rounded() * step
            e = CGPoint(x: start.x + len * cos(a), y: start.y + len * sin(a))
        }
        if fromCenter { return (CGPoint(x: 2 * start.x - e.x, y: 2 * start.y - e.y), e) }
        return (start, e)
    }

    /// Isosceles triangle inscribed in `r` (apex top-centre).
    static func trianglePoints(in r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    /// Regular polygon inscribed in the ellipse of `r`, first vertex at the top.
    static func polygonPoints(in r: CGRect, sides: Int) -> [CGPoint] {
        let n = min(max(sides, 3), 100)
        return (0..<n).map { i in
            let a = -CGFloat.pi / 2 + 2 * .pi * CGFloat(i) / CGFloat(n)
            return CGPoint(x: r.midX + r.width / 2 * cos(a), y: r.midY + r.height / 2 * sin(a))
        }
    }

    /// Arrow geometry: the shaft (shortened to the head base) and the filled head triangle.
    static func arrow(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat) -> (shaftEnd: CGPoint, head: [CGPoint]) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 0.001 else { return (b, []) }
        let headLen = min(max(lineWidth * 4, 12), len)
        let headHalf = headLen * 0.45
        let ux = dx / len, uy = dy / len
        let base = CGPoint(x: b.x - ux * headLen, y: b.y - uy * headLen)
        let head = [b,
                    CGPoint(x: base.x - uy * headHalf, y: base.y + ux * headHalf),
                    CGPoint(x: base.x + uy * headHalf, y: base.y - ux * headHalf)]
        return (CGPoint(x: b.x - ux * headLen * 0.8, y: b.y - uy * headLen * 0.8), head)
    }

    /// Smooth open path through `points` (Catmull-Rom converted to cubic Béziers).
    static func smoothPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 { path.addLine(to: first); return path }
        if points.count == 2 { path.addLine(to: points[1]); return path }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    static func polygonPath(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let f = pts.first else { return p }
        p.move(to: f)
        pts.dropFirst().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        return p
    }
}
