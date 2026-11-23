import AppKit

/// Rectangle (V) and free-form (L) selection, plus moving / resizing / rotating the selected
/// pixels as floating content.
///
/// Gestures: drag on empty canvas = new selection; drag inside the selection = lift & move;
/// drag a handle of floating content = resize / rotate. A plain click outside deselects
/// (undoable). Return / click outside / tool switch commits floating content, Escape cancels it.
final class SelectionTool: CanvasTool {
    let kind: ToolKind
    private var isLasso: Bool { kind == .lassoSelect }

    private enum Gesture {
        case none
        case creating(start: CGPoint, original: CanvasSelection?)
        case lassoing(points: [CGPoint], original: CanvasSelection?)
        case pendingLift(start: CGPoint)
        case moving(start: CGPoint, startTransform: CGAffineTransform)
        case resizing(HandleID, TransformFrame)
        case rotating(TransformFrame)
    }

    private var gesture = Gesture.none
    private var lastPoint = CGPoint.zero
    /// Rect / path produced by the current creation gesture.
    private var pendingSelection: CanvasSelection?
    private var context: ToolContext?
    private var syncGeneration = 0
    private var hoverCursor: NSCursor = .crosshair

    init(kind: ToolKind) { self.kind = kind }

    // MARK: - Lifecycle

    func activate(context: ToolContext) {
        self.context = context
        gesture = .none
        startStatusSync(context)
    }

    func deactivate(context: ToolContext) {
        cancel(context: context)
        context.canvas.commitFloatingIfNeeded()
        // Stop the status observation and let go of the canvas (tools outlive documents).
        syncGeneration += 1
        self.context = nil
    }

    /// Keeps `WindowState.selectionSize` / `imageSize` current (also after undo/redo).
    private func startStatusSync(_ ctx: ToolContext) {
        syncGeneration += 1
        let generation = syncGeneration
        observeContinuously(self) { tool in
            guard tool.syncGeneration == generation, let ctx = tool.context else { return }
            let c = ctx.canvas
            let size = c.floating?.bounds.size ?? c.selection?.bounds.size
            ctx.windowState.selectionSize = size.map { CGSize(width: $0.width.rounded(), height: $0.height.rounded()) }
            ctx.windowState.imageSize = c.size
        }
    }

    // MARK: - Mouse

    func mouseDown(_ event: ToolEvent, context: ToolContext) {
        let c = context.canvas
        let p = event.location
        lastPoint = p
        pendingSelection = nil

        if c.floating != nil {
            if let g = floatingGesture(at: p, context: context) { gesture = g; return }
            c.commitFloating()
        }
        if let sel = c.selection, sel.path.contains(p, using: .winding) {
            gesture = .pendingLift(start: p)
            return
        }
        let q = clamp(p, to: c.bounds)
        gesture = isLasso ? .lassoing(points: [q.rounded], original: c.selection) : .creating(start: q.rounded, original: c.selection)
    }

    func mouseDragged(_ event: ToolEvent, context: ToolContext) {
        let c = context.canvas
        let p = event.location
        lastPoint = p
        switch gesture {
        case .none:
            break
        case .creating(let start, _):
            let r = makeRect(from: start, to: clamp(p, to: c.bounds).rounded, square: event.shift, fromCenter: event.option, in: c.bounds)
            pendingSelection = r.isEmpty ? nil : .rect(r)
            c.setSelection(pendingSelection, undoable: false)
        case .lassoing(var pts, let original):
            let q = clamp(p, to: c.bounds).rounded
            if q != pts.last { pts.append(q) }
            gesture = .lassoing(points: pts, original: original)
            pendingSelection = polygon(pts)
            c.setSelection(pendingSelection, undoable: false)
        case .pendingLift(let start):
            let secondary = context.settings.transparentSelection ? context.settings.secondaryColor : nil
            guard c.liftSelection(transparentColor: secondary), let f = c.floating else { gesture = .none; return }
            gesture = .moving(start: start, startTransform: f.transform)
            move(to: p, start: start, startTransform: f.transform, context: context)
        case .moving(let start, let startTransform):
            move(to: p, start: start, startTransform: startTransform, context: context)
        case .resizing(let handle, let frame):
            c.setFloatingTransform(frame.resized(handle: handle, to: p, keepAspect: event.shift).transform)
        case .rotating(let frame):
            c.setFloatingTransform(frame.rotated(toward: p, snap: event.shift).transform)
        }
        context.setNeedsOverlayDisplay()
    }

    func mouseUp(_ event: ToolEvent, context: ToolContext) {
        let c = context.canvas
        defer { gesture = .none; pendingSelection = nil; context.setNeedsOverlayDisplay() }
        switch gesture {
        case .creating(_, let original), .lassoing(_, let original):
            if let new = pendingSelection, new.bounds.width >= 1, new.bounds.height >= 1 {
                c.setSelection(original, undoable: false)
                c.setSelection(new, undoable: true, actionName: String(localized: "Select", table: "Paint"))
            } else {
                // A click: deselect.
                c.setSelection(original, undoable: false)
                if original != nil { c.setSelection(nil, undoable: true, actionName: String(localized: "Deselect", table: "Paint")) }
            }
        default:
            break
        }
    }

    func mouseMoved(_ event: ToolEvent, context: ToolContext) {
        lastPoint = event.location
        let cursor = cursor(at: event.location, context: context)
        if cursor !== hoverCursor {
            hoverCursor = cursor
            context.view.refreshCursor()
        }
    }

    func flagsChanged(_ event: ToolEvent, context: ToolContext) {
        switch gesture {
        case .creating, .resizing, .rotating: mouseDragged(event, context: context)
        default: break
        }
    }

    func cancel(context: ToolContext) {
        switch gesture {
        case .creating(_, let original), .lassoing(_, let original):
            context.canvas.setSelection(original, undoable: false)
        default:
            break
        }
        gesture = .none
        pendingSelection = nil
    }

    // MARK: - Keyboard

    func keyDown(_ event: NSEvent, context: ToolContext) -> Bool {
        let c = context.canvas
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])
        switch event.keyCode {
        case 36, 76:  // Return / Enter
            guard c.floating != nil else { return false }
            c.commitFloating()
            return true
        case 53:  // Escape
            guard c.floating != nil else { return false }
            c.cancelFloating()
            return true
        case 123, 124, 125, 126:
            guard mods.isSubset(of: .shift), c.selection != nil || c.floating != nil else { return false }
            let step: CGFloat = mods.contains(.shift) ? 10 : 1
            let delta: (CGFloat, CGFloat) = switch event.keyCode {
            case 123: (-step, 0)
            case 124: (step, 0)
            case 125: (0, step)
            default: (0, -step)
            }
            if c.floating == nil {
                let secondary = context.settings.transparentSelection ? context.settings.secondaryColor : nil
                guard c.liftSelection(transparentColor: secondary) else { return false }
            }
            if let f = c.floating {
                c.setFloatingTransform(f.transform.concatenating(CGAffineTransform(translationX: delta.0, y: delta.1)))
            }
            context.setNeedsOverlayDisplay()
            return true
        default:
            return false
        }
    }

    // MARK: - Cursor & overlay

    func cursor(context: ToolContext) -> NSCursor { hoverCursor }

    private func cursor(at p: CGPoint, context: ToolContext) -> NSCursor {
        let c = context.canvas
        if let f = c.floating {
            guard let frame = frame(of: f) else { return .crosshair }
            let r = 7 / context.magnification
            if distance(p, frame.rotationHandlePoint(offset: rotationOffset(context))) <= r { return .pointingHand }
            for h in HandleID.allCases where distance(p, frame.handlePoint(h)) <= r { return h.cursor }
            return contains(f, p) ? .openHand : .crosshair
        }
        if let sel = c.selection, sel.path.contains(p, using: .winding) { return .openHand }
        return .crosshair
    }

    func drawOverlay(in ctx: CGContext, context: ToolContext) {
        guard let f = context.canvas.floating, let frame = frame(of: f) else { return }
        let mag = context.magnification
        HandleDrawing.strokePolygon(ctx, frame.corners, magnification: mag)
        let rot = frame.rotationHandlePoint(offset: rotationOffset(context))
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1 / mag)
        ctx.move(to: frame.point(0, -1))
        ctx.addLine(to: rot)
        ctx.strokePath()
        for h in HandleID.allCases { HandleDrawing.drawSquare(ctx, at: frame.handlePoint(h), magnification: mag) }
        HandleDrawing.drawCircle(ctx, at: rot, magnification: mag)
    }

    // MARK: - Helpers

    private func rotationOffset(_ context: ToolContext) -> CGFloat { 24 / context.magnification }

    private func frame(of f: FloatingContent) -> TransformFrame? {
        TransformFrame(transform: f.transform, local: CGSize(width: f.image.width, height: f.image.height))
    }

    private func contains(_ f: FloatingContent, _ p: CGPoint) -> Bool {
        guard abs(f.transform.a * f.transform.d - f.transform.b * f.transform.c) > 1e-9 else { return false }
        let q = p.applying(f.transform.inverted())
        return CGRect(x: 0, y: 0, width: f.image.width, height: f.image.height).contains(q)
    }

    private func floatingGesture(at p: CGPoint, context: ToolContext) -> Gesture? {
        guard let f = context.canvas.floating, let frame = frame(of: f) else { return nil }
        let r = 7 / context.magnification
        if distance(p, frame.rotationHandlePoint(offset: rotationOffset(context))) <= r { return .rotating(frame) }
        for h in HandleID.allCases where distance(p, frame.handlePoint(h)) <= r { return .resizing(h, frame) }
        if contains(f, p) { return .moving(start: p, startTransform: f.transform) }
        return nil
    }

    private func move(to p: CGPoint, start: CGPoint, startTransform: CGAffineTransform, context: ToolContext) {
        let dx = (p.x - start.x).rounded(), dy = (p.y - start.y).rounded()
        context.canvas.setFloatingTransform(startTransform.concatenating(CGAffineTransform(translationX: dx, y: dy)))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    /// Selection rectangle between two pixel-aligned points.
    private func makeRect(from a: CGPoint, to b: CGPoint, square: Bool, fromCenter: Bool, in bounds: CGRect) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if square {
            let m = max(abs(dx), abs(dy))
            dx = dx < 0 ? -m : m
            dy = dy < 0 ? -m : m
        }
        let r = fromCenter
            ? CGRect(x: a.x - abs(dx), y: a.y - abs(dy), width: abs(dx) * 2, height: abs(dy) * 2)
            : CGRect(x: min(a.x, a.x + dx), y: min(a.y, a.y + dy), width: abs(dx), height: abs(dy))
        return r.intersection(bounds).isNull ? .zero : r.intersection(bounds)
    }

    private func polygon(_ pts: [CGPoint]) -> CanvasSelection? {
        guard pts.count >= 3 else { return nil }
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        return CanvasSelection(path: path)
    }
}

private extension CGPoint {
    var rounded: CGPoint { CGPoint(x: x.rounded(), y: y.rounded()) }
}
