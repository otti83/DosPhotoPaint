import AppKit

/// The eight resize handles of a rectangle, as unit offsets from its centre.
enum HandleID: CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    /// (-1, 0, 1) per axis; y-down (top = -1).
    var unit: (x: CGFloat, y: CGFloat) {
        switch self {
        case .topLeft: (-1, -1)
        case .top: (0, -1)
        case .topRight: (1, -1)
        case .left: (-1, 0)
        case .right: (1, 0)
        case .bottomLeft: (-1, 1)
        case .bottom: (0, 1)
        case .bottomRight: (1, 1)
        }
    }

    /// Position on an axis-aligned rect.
    func point(in r: CGRect) -> CGPoint {
        CGPoint(x: r.midX + unit.x * r.width / 2, y: r.midY + unit.y * r.height / 2)
    }

    var cursor: NSCursor {
        switch self {
        case .left, .right: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        default: .crosshair
        }
    }
}

/// Decomposition of a floating-content transform into centre, displayed size and angle
/// (no shear, no flips — the only transforms the selection tool produces).
struct TransformFrame {
    var center: CGPoint
    var size: CGSize
    var angle: CGFloat
    /// Size of the untransformed image.
    let local: CGSize

    init(transform t: CGAffineTransform, local: CGSize) {
        self.local = local
        angle = atan2(t.b, t.a)
        size = CGSize(width: max(1, local.width * hypot(t.a, t.b)), height: max(1, local.height * hypot(t.c, t.d)))
        center = CGPoint(x: local.width / 2, y: local.height / 2).applying(t)
    }

    var transform: CGAffineTransform {
        CGAffineTransform(translationX: -local.width / 2, y: -local.height / 2)
            .concatenating(CGAffineTransform(scaleX: size.width / local.width, y: size.height / local.height))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    private func rotate(_ p: CGPoint, by a: CGFloat) -> CGPoint {
        CGPoint(x: p.x * cos(a) - p.y * sin(a), y: p.x * sin(a) + p.y * cos(a))
    }

    /// Point at unit offset (ux, uy) ∈ [-1, 1]² from the centre, in canvas pixels.
    func point(_ ux: CGFloat, _ uy: CGFloat) -> CGPoint {
        let o = rotate(CGPoint(x: ux * size.width / 2, y: uy * size.height / 2), by: angle)
        return CGPoint(x: center.x + o.x, y: center.y + o.y)
    }

    func handlePoint(_ h: HandleID) -> CGPoint { point(h.unit.x, h.unit.y) }

    /// Rotation handle: above the top edge, `offset` canvas pixels away.
    func rotationHandlePoint(offset: CGFloat) -> CGPoint {
        let o = rotate(CGPoint(x: 0, y: -size.height / 2 - offset), by: angle)
        return CGPoint(x: center.x + o.x, y: center.y + o.y)
    }

    var corners: [CGPoint] { [point(-1, -1), point(1, -1), point(1, 1), point(-1, 1)] }

    /// Frame after dragging `handle` to canvas point `p`; the opposite edge/corner stays fixed.
    func resized(handle h: HandleID, to p: CGPoint, keepAspect: Bool) -> TransformFrame {
        let hx = h.unit.x, hy = h.unit.y
        let q = rotate(CGPoint(x: p.x - center.x, y: p.y - center.y), by: -angle)
        var nw = hx != 0 ? max(1, hx * q.x + size.width / 2) : size.width
        var nh = hy != 0 ? max(1, hy * q.y + size.height / 2) : size.height
        if keepAspect {
            let r: CGFloat = (hx != 0 && hy != 0) ? max(nw / size.width, nh / size.height) : (hx != 0 ? nw / size.width : nh / size.height)
            nw = max(1, size.width * r)
            nh = max(1, size.height * r)
        }
        let shift = rotate(CGPoint(x: hx != 0 ? hx * (nw - size.width) / 2 : 0, y: hy != 0 ? hy * (nh - size.height) / 2 : 0), by: angle)
        var f = self
        f.size = CGSize(width: nw, height: nh)
        f.center = CGPoint(x: center.x + shift.x, y: center.y + shift.y)
        return f
    }

    /// Frame rotated so the rotation handle points at `p` (optionally snapped to 15° steps).
    func rotated(toward p: CGPoint, snap: Bool) -> TransformFrame {
        var a = atan2(p.y - center.y, p.x - center.x) + .pi / 2
        if snap { let step = CGFloat.pi / 12; a = (a / step).rounded() * step }
        var f = self
        f.angle = a
        return f
    }
}

/// Shared handle drawing.
enum HandleDrawing {
    static func drawSquare(_ ctx: CGContext, at p: CGPoint, magnification: CGFloat) {
        let s = 8 / magnification
        let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1 / magnification)
        ctx.fill(r)
        ctx.stroke(r)
    }

    static func drawCircle(_ ctx: CGContext, at p: CGPoint, magnification: CGFloat) {
        let s = 9 / magnification
        let r = CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)
        ctx.setFillColor(NSColor.controlAccentColor.cgColor)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1 / magnification)
        ctx.fillEllipse(in: r)
        ctx.strokeEllipse(in: r)
    }

    static func strokePolygon(_ ctx: CGContext, _ pts: [CGPoint], magnification: CGFloat) {
        guard let first = pts.first else { return }
        let lw = 1 / magnification
        ctx.setLineWidth(lw)
        for (color, dash) in [(NSColor.white, false), (NSColor.black, true)] {
            ctx.move(to: first)
            pts.dropFirst().forEach { ctx.addLine(to: $0) }
            ctx.closePath()
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineDash(phase: 0, lengths: dash ? [4 * lw, 4 * lw] : [])
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }
}
