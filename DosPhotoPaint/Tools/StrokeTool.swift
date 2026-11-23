import AppKit

/// Freehand pen, brush and eraser.
///
/// The gesture is painted at full strength into the canvas' live-preview scratch buffer and
/// composited with the tool opacity, so overlapping segments never darken a semi-transparent
/// stroke. On mouse-up the preview is merged into the layer as one undo step.
final class StrokeTool: CanvasTool {
    let kind: ToolKind
    private var lastPoint: CGPoint?
    private var lastWidth: CGFloat = 1
    /// Distance travelled since the last soft-brush dab (for even dab spacing).
    private var dabRemainder: CGFloat = 0
    private var hoverPoint: CGPoint?
    private var strokeColor: CGColor = .black
    /// Soft-brush gradient, built once per stroke/hardness. Creating a `CGGradient` (and converting
    /// the colour) for every dab dominated the cost of soft strokes.
    private var gradientCache: (hardness: CGFloat, gradient: CGGradient)?

    init(kind: ToolKind) {
        precondition([.pen, .brush, .eraser].contains(kind))
        self.kind = kind
    }

    // MARK: Parameters

    private func baseSize(_ s: ToolSettings) -> CGFloat {
        switch kind {
        case .pen: s.penWidth
        case .brush: s.brushSize
        default: s.eraserSize
        }
    }

    private func width(for event: ToolEvent, _ s: ToolSettings) -> CGFloat {
        let base = baseSize(s)
        guard event.isTablet, s.usePressure else { return base }
        return max(1, base * max(0.05, event.pressure))
    }

    /// Soft dabs for the soft brush; hard brush/pen/eraser use solid round strokes.
    private func usesDabs(_ s: ToolSettings) -> Bool {
        kind == .brush && (s.brushType == .soft || (s.brushType == .round && s.brushHardness < 0.99))
    }

    private func hardness(_ s: ToolSettings) -> CGFloat {
        switch s.brushType {
        case .soft: min(s.brushHardness, 0.5)
        case .hard: 1
        case .round: s.brushHardness
        }
    }

    // MARK: Events

    func mouseDown(_ event: ToolEvent, context: ToolContext) {
        let canvas = context.canvas
        let s = context.settings
        guard let layer = canvas.activeLayer else { return }
        guard layer.isVisible else { NSSound.beep(); return }
        canvas.commitFloatingIfNeeded()

        var blend: CGBlendMode = .normal
        var opacity = s.opacity
        var color = s.primaryColor
        if kind == .eraser {
            let isBackground = canvas.layers.first?.id == layer.id
            if s.eraserMode == .backgroundColorOnBackgroundLayer && isBackground {
                color = s.secondaryColor
            } else {
                blend = .destinationOut
                color = .black
            }
            opacity = 1
        } else {
            // The colour's own alpha joins the tool opacity so every brush type (including soft
            // dabs, which are built from an opaque colour) honours it uniformly.
            opacity *= Double(color.usingColorSpace(.sRGB)?.alphaComponent ?? 1)
        }
        strokeColor = color.usingColorSpace(.sRGB)?.withAlphaComponent(1).cgColor ?? .black
        gradientCache = nil
        guard let buffer = canvas.beginLivePreview(layerID: layer.id, opacity: opacity, blendMode: blend) else { return }
        configure(buffer.context, s)
        let w = width(for: event, s)
        let p = event.location
        if event.shift, let last = lastPoint {
            // Shift-click: straight line from the end of the previous stroke.
            drawSegment(from: last, to: p, width: w, buffer: buffer, canvas: canvas, settings: s)
        } else {
            dab(at: p, width: w, buffer: buffer, canvas: canvas, settings: s)
        }
        lastPoint = p
        lastWidth = w
        dabRemainder = 0
    }

    func mouseDragged(_ event: ToolEvent, context: ToolContext) {
        guard let last = lastPoint, let preview = context.canvas.livePreview else { return }
        let s = context.settings
        let w = width(for: event, s)
        drawSegment(from: last, to: event.location, width: w, buffer: preview.buffer, canvas: context.canvas, settings: s)
        lastPoint = event.location
        lastWidth = w
        moveHover(to: event.location, context: context)
    }

    func mouseUp(_ event: ToolEvent, context: ToolContext) {
        guard context.canvas.livePreview != nil else { return }
        let name: String = switch kind {
        case .pen: String(localized: "Pen", table: "Paint")
        case .brush: String(localized: "Brush", table: "Paint")
        default: String(localized: "Erase", table: "Paint")
        }
        context.canvas.commitLivePreview(actionName: name)
    }

    func mouseMoved(_ event: ToolEvent, context: ToolContext) {
        moveHover(to: event.location, context: context)
    }

    func cancel(context: ToolContext) {
        context.canvas.cancelLivePreview()
        lastPoint = nil
    }

    func deactivate(context: ToolContext) {
        lastPoint = nil
        if context.canvas.livePreview != nil { mouseUp(ToolEvent(location: .zero, pressure: 1, modifiers: [], clickCount: 0, isTablet: false), context: context) }
        hoverPoint = nil
        context.setNeedsOverlayDisplay()
    }

    func cursor(context: ToolContext) -> NSCursor { .crosshair }

    func drawOverlay(in ctx: CGContext, context: ToolContext) {
        guard let p = hoverPoint else { return }
        let size = baseSize(context.settings)
        guard size * context.magnification >= 4 else { return }
        let r = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        let lw = 1 / context.magnification
        ctx.setLineWidth(lw)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.strokeEllipse(in: r)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.strokeEllipse(in: r.insetBy(dx: lw, dy: lw))
    }

    private func moveHover(to p: CGPoint, context: ToolContext) {
        let size = baseSize(context.settings) + 4 / max(context.magnification, 0.01)
        let old = hoverPoint.map { CGRect(x: $0.x - size, y: $0.y - size, width: size * 2, height: size * 2) }
        hoverPoint = p
        let new = CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2)
        context.setNeedsOverlayDisplay(old.map { $0.union(new) } ?? new)
    }

    // MARK: Drawing

    private func configure(_ ctx: CGContext, _ s: ToolSettings) {
        let aa = AppSettings.shared.paintAntialiasing || kind == .brush
        ctx.setShouldAntialias(aa)
        ctx.setAllowsAntialiasing(aa)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(strokeColor)
        ctx.setFillColor(strokeColor)
        ctx.setBlendMode(.normal)
    }

    private func dab(at p: CGPoint, width w: CGFloat, buffer: RasterBuffer, canvas: CanvasModel, settings s: ToolSettings) {
        let rect = CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w)
        if usesDabs(s) {
            softDab(in: buffer.context, center: p, diameter: w, hardness: hardness(s))
        } else if !AppSettings.shared.paintAntialiasing && kind != .brush && w <= 1.5 {
            buffer.context.fill(CGRect(x: floor(p.x), y: floor(p.y), width: 1, height: 1))
        } else {
            buffer.context.fillEllipse(in: rect)
        }
        canvas.livePreviewDidChange(rect.insetBy(dx: -2, dy: -2))
    }

    private func drawSegment(from a: CGPoint, to b: CGPoint, width w: CGFloat, buffer: RasterBuffer, canvas: CanvasModel, settings s: ToolSettings) {
        let ctx = buffer.context
        if usesDabs(s) {
            let spacing = max(1, w * 0.12)
            let dx = b.x - a.x, dy = b.y - a.y
            let dist = hypot(dx, dy)
            var t = spacing - dabRemainder
            while t <= dist {
                let f = t / max(dist, 0.0001)
                let ww = lastWidth + (w - lastWidth) * f
                softDab(in: ctx, center: CGPoint(x: a.x + dx * f, y: a.y + dy * f), diameter: ww, hardness: hardness(s))
                t += spacing
            }
            dabRemainder = dist - (t - spacing)
        } else if !AppSettings.shared.paintAntialiasing && kind != .brush && w <= 1.5 {
            // Aliased 1-px pen: Bresenham-style pixel steps so diagonal lines stay 1 px wide.
            let steps = Int(max(abs(b.x - a.x), abs(b.y - a.y)).rounded(.up))
            for i in 0...max(steps, 1) {
                let f = CGFloat(i) / CGFloat(max(steps, 1))
                ctx.fill(CGRect(x: floor(a.x + (b.x - a.x) * f), y: floor(a.y + (b.y - a.y) * f), width: 1, height: 1))
            }
        } else {
            ctx.setLineWidth(w)
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }
        let pad = max(w, lastWidth) / 2 + 2
        let dirty = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)).insetBy(dx: -pad, dy: -pad)
        canvas.livePreviewDidChange(dirty)
    }

    /// Radial dab: opaque core of `hardness`·radius fading to transparent at the edge.
    private func softDab(in ctx: CGContext, center: CGPoint, diameter: CGFloat, hardness: CGFloat) {
        let radius = max(diameter / 2, 0.5)
        let h = min(max(hardness, 0), 0.99)
        if gradientCache?.hardness != h {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let c = strokeColor.converted(to: space, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
            let colors = [CGColor(colorSpace: space, components: [c[0], c[1], c[2], 1])!,
                          CGColor(colorSpace: space, components: [c[0], c[1], c[2], 0])!] as CFArray
            guard let g = CGGradient(colorsSpace: space, colors: colors, locations: [h, 1]) else { return }
            gradientCache = (h, g)
        }
        guard let gradient = gradientCache?.gradient else { return }
        // Clip to the dab: Core Graphics otherwise evaluates the gradient over the whole
        // (canvas-sized) clip region, which made every dab cost milliseconds on large canvases.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2).integral)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsBeforeStartLocation])
        ctx.restoreGState()
    }
}
