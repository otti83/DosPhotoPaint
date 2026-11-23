import AppKit
import Observation

/// App-level hint for the inspector buttons: is a crop rectangle pending in the active tool?
@Observable
final class CropStatus {
    static let shared = CropStatus()
    var hasPendingCrop = false
}

/// Crop tool (C): drag a rectangle (optionally with an aspect preset), adjust with handles,
/// Return / double-click applies, Escape cancels. Applying crops every layer (one undo step).
/// A pending, unapplied rectangle is not an edit and is simply dropped on tool switch.
final class CropTool: CanvasTool {
    let kind = ToolKind.crop

    private enum Gesture {
        case none
        case creating(anchor: CGPoint)
        case moving(start: CGPoint, startRect: CGRect)
        case resizing(HandleID, CGRect)
    }

    private(set) var rect: CGRect? {
        didSet { CropStatus.shared.hasPendingCrop = rect != nil }
    }
    private var gesture = Gesture.none
    private var lastPoint = CGPoint.zero
    private var hoverCursor: NSCursor = .crosshair

    // MARK: - Lifecycle

    func activate(context: ToolContext) {
        context.canvas.commitFloatingIfNeeded()
        rect = nil
        gesture = .none
        context.setNeedsOverlayDisplay()
    }

    func deactivate(context: ToolContext) {
        rect = nil
        context.windowState.selectionSize = context.canvas.selection?.bounds.size
        gesture = .none
        context.setNeedsOverlayDisplay()
    }

    func cancel(context: ToolContext) {
        gesture = .none
        context.setNeedsOverlayDisplay()
    }

    /// Applies the pending rectangle. Returns false if there is none.
    @discardableResult
    func apply(context: ToolContext) -> Bool {
        guard let r = rect else { return false }
        let canvas = context.canvas
        // Large images crop off the main actor; the window is busy meanwhile (no re-entrancy).
        if canvas.prefersOffloading, canvas.cropRect(for: r) != nil {
            guard context.windowState.beginBusy(String(localized: "Cropping…", table: "Paint")) else { return false }
            rect = nil
            gesture = .none
            Task {
                let ok = await canvas.cropOffloaded(to: r)
                context.windowState.endBusy()
                finishApply(ok, context: context)
            }
            return true
        }
        rect = nil
        gesture = .none
        let ok = canvas.crop(to: r)
        finishApply(ok, context: context)
        return ok
    }

    private func finishApply(_ ok: Bool, context: ToolContext) {
        context.windowState.selectionSize = nil
        context.windowState.imageSize = context.canvas.size
        context.setNeedsOverlayDisplay()
        if !ok { NSSound.beep() }
    }

    func discard(context: ToolContext) {
        rect = nil
        context.windowState.selectionSize = nil
        gesture = .none
        context.setNeedsOverlayDisplay()
    }

    // MARK: - Mouse

    func mouseDown(_ event: ToolEvent, context: ToolContext) {
        let bounds = context.canvas.bounds
        let p = clamp(event.location, to: bounds)
        lastPoint = p
        if let r = rect {
            if event.clickCount >= 2, r.contains(p) { apply(context: context); return }
            if let h = handle(at: event.location, in: r, context: context) { gesture = .resizing(h, r); return }
            if r.contains(p) { gesture = .moving(start: p, startRect: r); return }
        }
        rect = nil
        gesture = .creating(anchor: p.rounded)
        context.setNeedsOverlayDisplay()
    }

    func mouseDragged(_ event: ToolEvent, context: ToolContext) {
        let bounds = context.canvas.bounds
        let p = clamp(event.location, to: bounds)
        lastPoint = p
        let ratio = aspectRatio(context)
        switch gesture {
        case .none:
            break
        case .creating(let anchor):
            rect = created(from: anchor, to: p.rounded, ratio: ratio)
        case .moving(let start, let startRect):
            var r = startRect.offsetBy(dx: (p.x - start.x).rounded(), dy: (p.y - start.y).rounded())
            r.origin.x = min(max(r.origin.x, bounds.minX), bounds.maxX - r.width)
            r.origin.y = min(max(r.origin.y, bounds.minY), bounds.maxY - r.height)
            rect = r
        case .resizing(let h, let startRect):
            rect = resized(startRect, handle: h, to: p, bounds: bounds, ratio: ratio)
        }
        context.windowState.selectionSize = rect.map { CGSize(width: $0.width.rounded(), height: $0.height.rounded()) }
        context.setNeedsOverlayDisplay()
    }

    func mouseUp(_ event: ToolEvent, context: ToolContext) {
        if case .creating = gesture, let r = rect, r.width < 2 || r.height < 2 { rect = nil }
        gesture = .none
        context.setNeedsOverlayDisplay()
    }

    func mouseMoved(_ event: ToolEvent, context: ToolContext) {
        lastPoint = event.location
        var cursor: NSCursor = .crosshair
        if let r = rect {
            if let h = handle(at: event.location, in: r, context: context) { cursor = h.cursor }
            else if r.contains(event.location) { cursor = .openHand }
        }
        if cursor !== hoverCursor { hoverCursor = cursor; context.view.refreshCursor() }
    }

    func cursor(context: ToolContext) -> NSCursor { hoverCursor }

    func keyDown(_ event: NSEvent, context: ToolContext) -> Bool {
        switch event.keyCode {
        case 36, 76: return apply(context: context)
        case 53:
            guard rect != nil else { return false }
            discard(context: context)
            return true
        default: return false
        }
    }

    // MARK: - Overlay

    func drawOverlay(in ctx: CGContext, context: ToolContext) {
        guard let r = rect else { return }
        let mag = context.magnification
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.addRect(context.canvas.bounds)
        ctx.addRect(r)
        ctx.fillPath(using: .evenOdd)

        // Rule-of-thirds guides.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1 / mag)
        for i in 1...2 {
            let f = CGFloat(i) / 3
            ctx.move(to: CGPoint(x: r.minX + r.width * f, y: r.minY)); ctx.addLine(to: CGPoint(x: r.minX + r.width * f, y: r.maxY))
            ctx.move(to: CGPoint(x: r.minX, y: r.minY + r.height * f)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * f))
        }
        ctx.strokePath()

        HandleDrawing.strokePolygon(ctx, [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                                          CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)], magnification: mag)
        for h in HandleID.allCases { HandleDrawing.drawSquare(ctx, at: h.point(in: r), magnification: mag) }
    }

    // MARK: - Geometry

    private func aspectRatio(_ context: ToolContext) -> CGFloat? {
        switch context.settings.cropAspect {
        case .original: CGFloat(context.canvas.width) / CGFloat(max(1, context.canvas.height))
        default: context.settings.cropAspect.ratio
        }
    }

    private func handle(at p: CGPoint, in r: CGRect, context: ToolContext) -> HandleID? {
        let tol = 7 / context.magnification
        return HandleID.allCases.first { hypot(p.x - $0.point(in: r).x, p.y - $0.point(in: r).y) <= tol }
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    private func created(from a: CGPoint, to p: CGPoint, ratio: CGFloat?) -> CGRect? {
        let dx = p.x - a.x, dy = p.y - a.y
        var w = abs(dx), h = abs(dy)
        if let ratio {
            if w / ratio <= h { h = (w / ratio).rounded() } else { w = (h * ratio).rounded() }
        }
        guard w >= 1, h >= 1 else { return nil }
        return CGRect(x: dx >= 0 ? a.x : a.x - w, y: dy >= 0 ? a.y : a.y - h, width: w, height: h)
    }

    private func resized(_ r: CGRect, handle h: HandleID, to p: CGPoint, bounds b: CGRect, ratio: CGFloat?) -> CGRect {
        let hx = h.unit.x, hy = h.unit.y
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        let px = p.x.rounded(), py = p.y.rounded()
        if hx < 0 { minX = min(px, maxX - 1) } else if hx > 0 { maxX = max(px, minX + 1) }
        if hy < 0 { minY = min(py, maxY - 1) } else if hy > 0 { maxY = max(py, minY + 1) }
        let out = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let ratio else { return out }

        var w = out.width, hh = out.height
        var x = out.minX, y = out.minY
        if hx != 0 && hy != 0 {
            if w / hh > ratio { w = hh * ratio } else { hh = w / ratio }
            w = max(1, w.rounded()); hh = max(1, hh.rounded())
            x = hx < 0 ? r.maxX - w : r.minX
            y = hy < 0 ? r.maxY - hh : r.minY
        } else if hx != 0 {
            hh = w / ratio
            let allowed = 2 * min(r.midY - b.minY, b.maxY - r.midY)
            if hh > allowed { hh = allowed; w = hh * ratio }
            w = max(1, w.rounded()); hh = max(1, hh.rounded())
            x = hx < 0 ? r.maxX - w : r.minX
            y = (r.midY - hh / 2).rounded()
        } else {
            w = hh * ratio
            let allowed = 2 * min(r.midX - b.minX, b.maxX - r.midX)
            if w > allowed { w = allowed; hh = w / ratio }
            w = max(1, w.rounded()); hh = max(1, hh.rounded())
            y = hy < 0 ? r.maxY - hh : r.minY
            x = (r.midX - w / 2).rounded()
        }
        return CGRect(x: x, y: y, width: w, height: hh).intersection(b)
    }
}

private extension CGPoint {
    var rounded: CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
}
