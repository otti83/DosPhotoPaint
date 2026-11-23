import AppKit
import Observation

/// Last colour picked with the eyedropper (shown in the inspector).
@Observable
final class EyedropperState {
    static let shared = EyedropperState()
    struct Sample: Equatable {
        var color: NSColor
        var r: Int, g: Int, b: Int
        /// 0…255
        var a: Int
        var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
        var alphaPercent: Int { Int((Double(a) / 255 * 100).rounded()) }
    }
    var lastPicked: Sample?
}

/// Picks the composite (visible, all layers) colour under the pointer.
/// Click = primary colour, Option-click = secondary colour. A swatch HUD with RGB / HEX / alpha
/// follows the pointer.
final class EyedropperTool: CanvasTool {
    let kind = ToolKind.eyedropper
    private var hover: (point: CGPoint, sample: EyedropperState.Sample)?

    func mouseDown(_ event: ToolEvent, context: ToolContext) {
        guard let s = sample(at: event.location, context: context) else { NSSound.beep(); return }
        update(hover: event.location, sample: s, context: context)
        pick(s, secondary: event.option, context: context)
    }

    func mouseDragged(_ event: ToolEvent, context: ToolContext) {
        guard let s = sample(at: event.location, context: context) else { clearHover(context); return }
        update(hover: event.location, sample: s, context: context)
        pick(s, secondary: event.option, context: context)
    }

    func mouseMoved(_ event: ToolEvent, context: ToolContext) {
        guard let s = sample(at: event.location, context: context) else { clearHover(context); return }
        update(hover: event.location, sample: s, context: context)
    }

    func deactivate(context: ToolContext) { clearHover(context) }
    func cancel(context: ToolContext) { clearHover(context) }

    func cursor(context: ToolContext) -> NSCursor { .crosshair }

    // MARK: Picking

    private func pick(_ s: EyedropperState.Sample, secondary: Bool, context: ToolContext) {
        if secondary { context.settings.secondaryColor = s.color } else { context.settings.primaryColor = s.color }
        EyedropperState.shared.lastPicked = s
    }

    private func sample(at p: CGPoint, context: ToolContext) -> EyedropperState.Sample? {
        let canvas = context.canvas
        let x = Int(floor(p.x)), y = Int(floor(p.y))
        guard let c = canvas.compositeColor(atX: x, y: y) else { return nil }
        let cg = CGColor(colorSpace: canvas.colorSpace, components: [c.r, c.g, c.b, c.a].map { CGFloat($0) })
        guard let cg, let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return EyedropperState.Sample(color: ns, r: byte(ns.redComponent), g: byte(ns.greenComponent),
                                      b: byte(ns.blueComponent), a: byte(ns.alphaComponent))
    }

    // MARK: HUD

    private static let hudSize = CGSize(width: 176, height: 46)

    /// HUD rect in pixel space (screen size divided by zoom), placed down-right of the pointer.
    private func hudRect(at p: CGPoint, context: ToolContext) -> CGRect {
        let m = max(context.magnification, 0.001)
        return CGRect(x: p.x + 16 / m, y: p.y + 16 / m, width: Self.hudSize.width / m, height: Self.hudSize.height / m)
    }

    private func update(hover point: CGPoint, sample: EyedropperState.Sample, context: ToolContext) {
        let old = hover.map { hudRect(at: $0.point, context: context).insetBy(dx: -8, dy: -8) }
        hover = (point, sample)
        let new = hudRect(at: point, context: context).insetBy(dx: -8, dy: -8)
        context.setNeedsOverlayDisplay(old.map { $0.union(new) } ?? new)
    }

    private func clearHover(_ context: ToolContext) {
        guard let h = hover else { return }
        hover = nil
        context.setNeedsOverlayDisplay(hudRect(at: h.point, context: context).insetBy(dx: -8, dy: -8))
    }

    func drawOverlay(in ctx: CGContext, context: ToolContext) {
        guard let (point, s) = hover else { return }
        let m = max(context.magnification, 0.001)
        let rect = hudRect(at: point, context: context)
        ctx.saveGState()
        // Work in screen points anchored at the HUD origin.
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: 1 / m, y: 1 / m)
        let box = CGRect(origin: .zero, size: Self.hudSize)
        let bg = CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(bg)
        ctx.setFillColor(NSColor(white: 0.1, alpha: 0.85).cgColor)
        ctx.fillPath()
        // Swatch over a small checkerboard-free backing so alpha is visible against dark.
        let sw = CGRect(x: 7, y: 7, width: 32, height: 32)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(sw)
        ctx.setFillColor(NSColor.lightGray.cgColor)
        ctx.fill(CGRect(x: sw.minX, y: sw.minY, width: 16, height: 16))
        ctx.fill(CGRect(x: sw.minX + 16, y: sw.minY + 16, width: 16, height: 16))
        ctx.setFillColor(s.color.cgColor)
        ctx.fill(sw)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(sw.insetBy(dx: 0.5, dy: 0.5))

        let lines = ["RGB \(s.r), \(s.g), \(s.b)", "\(s.hex)  α \(s.alphaPercent)%"]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white,
        ]
        let prev = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: 47, y: 8 + CGFloat(i) * 16), withAttributes: attrs)
        }
        NSGraphicsContext.current = prev
        ctx.restoreGState()

        // Ring around the sampled pixel when zoomed in.
        if m >= 4 {
            let px = CGRect(x: floor(point.x), y: floor(point.y), width: 1, height: 1)
            ctx.setLineWidth(1 / m)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(px)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.stroke(px.insetBy(dx: 1 / m, dy: 1 / m))
        }
    }
}
