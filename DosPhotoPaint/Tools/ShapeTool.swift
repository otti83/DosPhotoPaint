import AppKit

/// Line, rectangle, rounded rectangle, ellipse, circle, triangle, polygon, arrow and curve.
///
/// Live preview while dragging; the gesture commits as one undo step. Shift constrains (square / circle / 45° line), Option draws from the centre,
/// Escape cancels. Stroke uses the primary colour, fill the secondary colour.
final class ShapeTool: CanvasTool {
    let kind = ToolKind.shape
    private var start: CGPoint?
    private var current: CGPoint = .zero
    private var modifiers: NSEvent.ModifierFlags = []
    /// Freehand samples for the curve shape.
    private var curvePoints: [CGPoint] = []

    func mouseDown(_ event: ToolEvent, context: ToolContext) {
        let canvas = context.canvas
        guard let layer = canvas.activeLayer else { return }
        guard layer.isVisible else { NSSound.beep(); return }
        canvas.commitFloatingIfNeeded()
        guard canvas.beginLivePreview(layerID: layer.id, opacity: context.settings.opacity) != nil else { return }
        start = event.location
        current = event.location
        modifiers = event.modifiers
        curvePoints = [event.location]
    }

    func mouseDragged(_ event: ToolEvent, context: ToolContext) {
        guard start != nil else { return }
        current = event.location
        modifiers = event.modifiers
        if context.settings.shapeKind == .curve, curvePoints.last.map({ hypot($0.x - current.x, $0.y - current.y) >= 1.5 }) ?? true {
            curvePoints.append(current)
        }
        redraw(context)
    }

    func flagsChanged(_ event: ToolEvent, context: ToolContext) {
        guard start != nil else { return }
        modifiers = event.modifiers
        redraw(context)
    }

    func mouseUp(_ event: ToolEvent, context: ToolContext) {
        guard let s = start else { return }
        current = event.location
        modifiers = event.modifiers
        defer { reset() }
        let isCurve = context.settings.shapeKind == .curve
        // A freehand curve that loops back to its start is still a valid shape.
        let moved = hypot(current.x - s.x, current.y - s.y) >= 1 || (isCurve && curvePoints.count > 2)
        guard moved else { context.canvas.cancelLivePreview(); return }
        if isCurve, curvePoints.last != current { curvePoints.append(current) }
        redraw(context)
        context.canvas.commitLivePreview(actionName: String(localized: "Shape", table: "Paint"))
    }

    func cancel(context: ToolContext) {
        guard start != nil else { return }
        context.canvas.cancelLivePreview()
        reset()
    }

    func deactivate(context: ToolContext) { cancel(context: context) }

    func keyDown(_ event: NSEvent, context: ToolContext) -> Bool {
        guard start != nil, event.keyCode == 53 else { return false }
        cancel(context: context)
        return true
    }

    func cursor(context: ToolContext) -> NSCursor { .crosshair }

    private func reset() {
        start = nil
        curvePoints = []
    }

    // MARK: Drawing

    private func redraw(_ context: ToolContext) {
        guard let start, let preview = context.canvas.livePreview else { return }
        context.canvas.clearLivePreview()
        let rect = Self.draw(kind: context.settings.shapeKind, start: start, end: current, curve: curvePoints,
                             modifiers: modifiers, settings: context.settings, in: preview.buffer.context)
        context.canvas.livePreviewDidChange(rect)
    }

    /// Draws the shape into `ctx` (y-down pixel space). Returns the touched rect.
    @discardableResult
    static func draw(kind: ShapeKind, start: CGPoint, end: CGPoint, curve: [CGPoint],
                     modifiers: NSEvent.ModifierFlags, settings s: ToolSettings, in ctx: CGContext) -> CGRect {
        let shift = modifiers.contains(.shift), option = modifiers.contains(.option)
        let lw = max(CGFloat(s.shapeLineWidth), 1)
        let isClosed = ![.line, .arrow, .curve].contains(kind)
        let stroke = s.shapeStrokeEnabled || !s.shapeFillEnabled || !isClosed
        let fill = s.shapeFillEnabled && isClosed
        let strokeColor = s.primaryColor.usingColorSpace(.sRGB)?.cgColor ?? NSColor.black.cgColor
        let fillColor = s.secondaryColor.usingColorSpace(.sRGB)?.cgColor ?? NSColor.white.cgColor

        ctx.saveGState()
        defer { ctx.restoreGState() }
        let aa = AppSettings.shared.paintAntialiasing
        ctx.setShouldAntialias(aa)
        ctx.setAllowsAntialiasing(aa)
        ctx.setLineWidth(lw)
        ctx.setLineJoin(kind == .rectangle || kind == .triangle || kind == .polygon ? .miter : .round)
        ctx.setLineCap(.round)
        ctx.setMiterLimit(2)
        ctx.setStrokeColor(strokeColor)
        ctx.setFillColor(fillColor)

        func paint(_ path: CGPath) {
            if fill { ctx.addPath(path); ctx.fillPath() }
            if stroke { ctx.addPath(path); ctx.strokePath() }
        }

        var touched: CGRect
        switch kind {
        case .line:
            let (a, b) = ShapeGeometry.line(start: start, end: end, constrain: shift, fromCenter: option)
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            touched = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .arrow:
            let (a, b) = ShapeGeometry.line(start: start, end: end, constrain: shift, fromCenter: option)
            let geo = ShapeGeometry.arrow(from: a, to: b, lineWidth: lw)
            ctx.move(to: a); ctx.addLine(to: geo.shaftEnd); ctx.strokePath()
            if !geo.head.isEmpty {
                let head = ShapeGeometry.polygonPath(geo.head)
                ctx.setFillColor(strokeColor)
                ctx.addPath(head); ctx.fillPath()
                ctx.addPath(head); ctx.strokePath()
            }
            touched = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                .union(geo.head.isEmpty ? .null : ShapeGeometry.polygonPath(geo.head).boundingBox)
        case .curve:
            let path = ShapeGeometry.smoothPath(through: curve.isEmpty ? [start, end] : curve)
            ctx.addPath(path); ctx.strokePath()
            touched = path.boundingBoxOfPath
        default:
            let square = shift || kind == .circle
            let box = ShapeGeometry.box(start: start, end: end, square: square, fromCenter: option)
            switch kind {
            case .rectangle: paint(CGPath(rect: box, transform: nil))
            case .roundedRectangle:
                let r = min(CGFloat(s.cornerRadius), box.width / 2, box.height / 2)
                paint(CGPath(roundedRect: box, cornerWidth: r, cornerHeight: r, transform: nil))
            case .ellipse, .circle: paint(CGPath(ellipseIn: box, transform: nil))
            case .triangle: paint(ShapeGeometry.polygonPath(ShapeGeometry.trianglePoints(in: box)))
            default: paint(ShapeGeometry.polygonPath(ShapeGeometry.polygonPoints(in: box, sides: s.polygonSides)))
            }
            touched = box
        }
        // Pad for stroke width, miter joins and antialiasing.
        let pad = (stroke ? lw * 1.5 : 0) + 3
        return touched.insetBy(dx: -pad, dy: -pad)
    }
}
