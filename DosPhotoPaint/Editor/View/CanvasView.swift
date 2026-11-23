import AppKit

/// What the canvas view displays.
enum CanvasContent {
    case none
    /// Photo Mode before the document is materialized: a (possibly downsampled) display image
    /// stretched over the full image pixel size.
    case preview(CGImage, pixelSize: CGSize)
    /// Editable canvas (both modes once materialized).
    case canvas(CanvasModel)
}

/// Events the canvas view cannot handle itself.
protocol CanvasViewDelegate: AnyObject {
    /// Active tool in Paint Mode; nil in Photo Mode.
    var activeTool: CanvasTool? { get }
    var toolContext: ToolContext? { get }
    var isPaintMode: Bool { get }
    func canvasView(_ view: CanvasView, keyDown event: NSEvent) -> Bool
    func canvasView(_ view: CanvasView, keyUp event: NSEvent) -> Bool
    func canvasView(_ view: CanvasView, doubleClickAt pixel: CGPoint)
    func canvasView(_ view: CanvasView, pointerMovedTo pixel: CGPoint?)
    func canvasView(_ view: CanvasView, draggingEntered info: NSDraggingInfo) -> NSDragOperation
    func canvasView(_ view: CanvasView, performDrop info: NSDraggingInfo) -> Bool
    func canvasViewDraggingExited(_ view: CanvasView)
    func canvasView(_ view: CanvasView, menuFor event: NSEvent) -> NSMenu?
}

/// The document view: draws the image/canvas in **image pixel coordinates** (1 px = 1 pt at
/// magnification 1, y-down) and turns mouse events into `ToolEvent`s.
final class CanvasView: NSView {
    weak var delegate: CanvasViewDelegate?

    var content: CanvasContent = .none {
        didSet { contentDidChange() }
    }

    /// Background colour around the image (provided by the scroll view) and checkerboard flag.
    var showsCheckerboard = true { didSet { needsDisplay = true } }
    /// Interpolation preference for scaled drawing.
    var interpolation: InterpolationSetting = .automatic { didSet { needsDisplay = true } }
    /// Quarter-turn display rotation applied in Photo Mode for unmaterialized previews is NOT
    /// supported: rotations are real edits (see ImageDocument).

    /// Visual drop feedback.
    var isDropTarget = false { didSet { needsDisplay = true } }

    private var trackingArea: NSTrackingArea?
    private var panOrigin: NSPoint?
    private var panStart: NSPoint?
    /// Photo Mode: asked to start a drag-out session once a drag moved a few points; returns true
    /// if it did (the image fits, nothing to pan). See Viewer/ViewerCoordinator.
    var dragOutProvider: ((NSEvent) -> Bool)?
    private(set) var isSpacePanning = false
    private var isToolGestureActive = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        registerForDraggedTypes([.fileURL, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityLabel() -> String? {
        delegate?.isPaintMode == true ? String(localized: "Canvas", table: "Paint") : String(localized: "Image", table: "Viewer")
    }

    override func accessibilityValue() -> Any? {
        guard bounds.width > 0 else { return nil }
        return String(localized: "\(Int(bounds.width)) by \(Int(bounds.height)) pixels, zoom \(Int((magnification * 100).rounded())) percent", table: "Viewer")
    }

    var scrollView: CanvasScrollView? { enclosingScrollView as? CanvasScrollView }
    var magnification: CGFloat { scrollView?.magnification ?? 1 }

    var canvasModel: CanvasModel? {
        if case .canvas(let m) = content { return m }
        return nil
    }

    var pixelSize: CGSize {
        switch content {
        case .none: .zero
        case .preview(_, let size): size
        case .canvas(let m): m.size
        }
    }

    private func contentDidChange() {
        if case .canvas(let model) = content {
            model.onInvalidate = { [weak self] rect in self?.setNeedsDisplayForPixels(rect) }
            model.onSizeChange = { [weak self] in self?.updateFrameSize() }
            model.onSelectionChange = { [weak self] in self?.needsDisplay = true }
        }
        updateFrameSize()
        needsDisplay = true
    }

    func updateFrameSize() {
        let size = pixelSize
        if frame.size != size { setFrameSize(size) }
        needsDisplay = true
    }

    /// Marks a pixel rect dirty, padded for smoothing at fractional zoom.
    func setNeedsDisplayForPixels(_ rect: CGRect) {
        let pad = max(2, ceil(2 / max(magnification, 0.01)))
        setNeedsDisplay(rect.insetBy(dx: -pad, dy: -pad))
    }

    func setNeedsOverlayDisplay(_ rect: CGRect?) {
        if let rect { setNeedsDisplayForPixels(rect) } else { needsDisplay = true }
    }

    // MARK: - Drawing

    private static let checkerColor: NSColor = {
        let size = 16
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(white: 0.94, alpha: 1).setFill(); rect.fill()
            NSColor(white: 0.80, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: image)
    }()

    private func interpolationQuality(paint: Bool) -> CGInterpolationQuality {
        let z = magnification
        switch interpolation {
        case .nearestNeighbor: return .none
        case .smooth: return z >= 1 && paint ? .none : .high
        case .automatic:
            if z >= 2 || (paint && z >= 1) { return .none }
            return AppSettings.shared.performanceHighQualityInterpolation ? .high : .medium
        }
    }

    private var previewIsOpaque: Bool {
        guard case .preview(let image, _) = content else { return false }
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: return false
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let imageRect = bounds
        let visible = dirtyRect.intersection(imageRect)
        guard !visible.isEmpty else { return }

        // The checkerboard only shows through transparent pixels; an opaque preview (JPEG…) hides it
        // completely, and filling the pattern under a full-screen image doubled the draw cost.
        if showsCheckerboard, !previewIsOpaque {
            NSGraphicsContext.saveGraphicsState()
            Self.checkerColor.setFill()
            visible.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        switch content {
        case .none:
            break
        case .preview(let image, _):
            ctx.saveGState()
            ctx.interpolationQuality = interpolationQuality(paint: false)
            ctx.drawUpright(image, in: imageRect)
            ctx.restoreGState()
        case .canvas(let model):
            model.updateComposite()
            // Draw a slightly larger source rect than needed so smoothing near the dirty-rect
            // edge samples real neighbours, then clip to the dirty rect.
            let pad = max(1, ceil(2 / max(magnification, 0.01)))
            let src = visible.insetBy(dx: -pad, dy: -pad).integral.intersection(imageRect)
            ctx.saveGState()
            ctx.clip(to: visible)
            ctx.interpolationQuality = interpolationQuality(paint: true)
            model.composite.withImage(in: src) { ctx.drawUpright($0, in: src) }
            ctx.restoreGState()
            drawGrids(in: ctx, rect: visible)
            drawSelection(model, in: ctx)
        }

        if let tool = delegate?.activeTool, let tc = delegate?.toolContext {
            ctx.saveGState()
            tool.drawOverlay(in: ctx, context: tc)
            ctx.restoreGState()
        }

        if isDropTarget {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: visibleRect.insetBy(dx: 2 / magnification, dy: 2 / magnification))
            path.lineWidth = 4 / magnification
            path.stroke()
        }
    }

    private func drawGrids(in ctx: CGContext, rect: CGRect) {
        let s = AppSettings.shared
        let z = magnification
        let hairline = 1 / z
        if s.paintPixelGrid == .highZoom && z >= 8 {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(white: 0.5, alpha: 0.35).cgColor)
            ctx.setLineWidth(hairline)
            var x = floor(rect.minX)
            while x <= rect.maxX { ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY)); x += 1 }
            var y = floor(rect.minY)
            while y <= rect.maxY { ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y)); y += 1 }
            ctx.strokePath()
            ctx.restoreGState()
        }
        if s.paintShowGrid, delegate?.isPaintMode == true {
            let step = CGFloat(s.paintGridSpacing)
            guard step * z >= 4 else { return }
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(hairline)
            var x = floor(rect.minX / step) * step
            while x <= rect.maxX { ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
            var y = floor(rect.minY / step) * step
            while y <= rect.maxY { ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private func drawSelection(_ model: CanvasModel, in ctx: CGContext) {
        guard AppSettings.shared.paintShowSelectionOutline, let sel = model.selection else { return }
        let lw = 1 / magnification
        ctx.saveGState()
        ctx.setLineWidth(lw)
        ctx.addPath(sel.path)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.strokePath()
        ctx.addPath(sel.path)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4 * lw, 4 * lw])
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Mouse

    func pixelLocation(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func toolEvent(_ event: NSEvent) -> ToolEvent {
        let isTablet = event.subtype == .tabletPoint
        let pressure: CGFloat = isTablet ? CGFloat(event.pressure) : 1
        return ToolEvent(location: pixelLocation(for: event), pressure: pressure,
                         modifiers: event.modifierFlags, clickCount: event.clickCount, isTablet: isTablet)
    }

    private var wantsPan: Bool {
        guard delegate?.isPaintMode == true else { return true }
        return isSpacePanning || delegate?.activeTool?.kind == .hand
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { currentCursor().set() }

    func currentCursor() -> NSCursor {
        if panOrigin != nil { return .closedHand }
        if wantsPan {
            guard let sv = scrollView else { return .arrow }
            // Only offer panning when the image is larger than the view.
            let docSize = frame.size.applying(CGAffineTransform(scaleX: magnification, y: magnification))
            return (docSize.width > sv.contentSize.width + 0.5 || docSize.height > sv.contentSize.height + 0.5 || isSpacePanning) ? .openHand : .arrow
        }
        if let tool = delegate?.activeTool, let tc = delegate?.toolContext { return tool.cursor(context: tc) }
        return .arrow
    }

    func refreshCursor() {
        window?.invalidateCursorRects(for: self)
        if let window, let p = window.mouseLocationOutsideOfEventStream as NSPoint?,
           visibleRect.contains(convert(p, from: nil)) {
            currentCursor().set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2, delegate?.isPaintMode == false {
            delegate?.canvasView(self, doubleClickAt: pixelLocation(for: event))
            return
        }
        if wantsPan {
            panOrigin = event.locationInWindow
            panStart = panOrigin
            NSCursor.closedHand.set()
            return
        }
        guard let tool = delegate?.activeTool, let tc = delegate?.toolContext else { return }
        isToolGestureActive = true
        tool.mouseDown(toolEvent(event), context: tc)
    }

    override func mouseDragged(with event: NSEvent) {
        if let origin = panOrigin {
            let p = event.locationInWindow
            if let start = panStart, hypot(p.x - start.x, p.y - start.y) >= 4, dragOutProvider?(event) == true {
                panOrigin = nil
                panStart = nil
                return
            }
            scrollView?.pan(byScreenDelta: CGSize(width: p.x - origin.x, height: p.y - origin.y))
            panOrigin = p
            return
        }
        guard isToolGestureActive, let tool = delegate?.activeTool, let tc = delegate?.toolContext else { return }
        autoscroll(with: event)
        tool.mouseDragged(toolEvent(event), context: tc)
        delegate?.canvasView(self, pointerMovedTo: pixelLocation(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        if panOrigin != nil {
            panOrigin = nil
            currentCursor().set()
            return
        }
        guard isToolGestureActive else { return }
        isToolGestureActive = false
        guard let tool = delegate?.activeTool, let tc = delegate?.toolContext else { return }
        tool.mouseUp(toolEvent(event), context: tc)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = pixelLocation(for: event)
        delegate?.canvasView(self, pointerMovedTo: bounds.contains(p) ? p : nil)
        if let tool = delegate?.activeTool, let tc = delegate?.toolContext { tool.mouseMoved(toolEvent(event), context: tc) }
    }

    override func mouseExited(with event: NSEvent) {
        delegate?.canvasView(self, pointerMovedTo: nil)
    }

    override func flagsChanged(with event: NSEvent) {
        if isToolGestureActive, let tool = delegate?.activeTool, let tc = delegate?.toolContext,
           let window {
            let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            tool.flagsChanged(ToolEvent(location: loc, pressure: 1, modifiers: event.modifierFlags, clickCount: 0, isTablet: false), context: tc)
        }
        super.flagsChanged(with: event)
    }

    override func tabletPoint(with event: NSEvent) {
        // Pressure arrives with mouseDragged events (subtype tabletPoint); nothing extra needed.
        super.tabletPoint(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = delegate?.canvasView(self, menuFor: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    /// Cancels an in-progress tool gesture (Escape / mode switch).
    func cancelToolGesture() {
        guard isToolGestureActive else { return }
        isToolGestureActive = false
        if let tool = delegate?.activeTool, let tc = delegate?.toolContext { tool.cancel(context: tc) }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, delegate?.isPaintMode == true, !isToolGestureActive {  // Space: temporary hand tool
            if !event.isARepeat { isSpacePanning = true; refreshCursor() }
            return
        }
        if delegate?.canvasView(self, keyDown: event) == true { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49, isSpacePanning {
            isSpacePanning = false
            refreshCursor()
            return
        }
        if delegate?.canvasView(self, keyUp: event) == true { return }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        isSpacePanning = false
        return super.resignFirstResponder()
    }

    // MARK: - Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = delegate?.canvasView(self, draggingEntered: sender) ?? []
        isDropTarget = op != []
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.canvasView(self, draggingEntered: sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
        delegate?.canvasViewDraggingExited(self)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        return delegate?.canvasView(self, performDrop: sender) ?? false
    }
}
