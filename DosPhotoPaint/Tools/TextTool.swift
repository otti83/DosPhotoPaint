import AppKit

/// Text tool. Editing happens in a real `EditorTextView` (subview of `CanvasView`, image pixel
/// space). Commit renders the attributed string into the active layer as one undo step "Text".
///
/// Option changes (font, size, B/I/U, alignment, colour) apply to the WHOLE text of the active
/// box (not just the selection) — simple and predictable for a single-style text box.
/// Text colour is the primary colour (opacity is not applied).
final class TextTool: CanvasTool {
    let kind = ToolKind.text

    private enum Handle: CaseIterable { case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }
    private enum Gesture {
        case none
        case creating(start: CGPoint)
        case moving(grab: CGSize)
        case resizing(Handle, original: CGRect)
    }

    private(set) var box: CGRect?
    private(set) var textView: EditorTextView?
    private var gesture: Gesture = .none
    private var dragRect: CGRect?
    private var context: ToolContext?
    private var isObserving = false
    private var needsReapply = false

    private static let minSize = CGSize(width: 24, height: 16)

    // MARK: - Lifecycle

    func activate(context: ToolContext) {
        self.context = context
        if !isObserving {
            isObserving = true
            observeContinuously(self) { $0.settingsDidChange() }
        }
        NSFontManager.shared.setSelectedFont(Self.font(for: context.settings), isMultiple: false)
    }

    func deactivate(context: ToolContext) {
        // A box that cannot be committed (e.g. hidden layer) must not outlive the tool.
        if !commit(force: true) { discard() }
        gesture = .none
        dragRect = nil
        self.context = nil
    }

    func cancel(context: ToolContext) {
        // Aborts the gesture only; an already placed box stays.
        if case .creating = gesture { dragRect = nil; context.setNeedsOverlayDisplay() }
        gesture = .none
    }

    func cursor(context: ToolContext) -> NSCursor { .crosshair }

    // MARK: - Options → attributes

    static func font(for s: ToolSettings) -> NSFont {
        let size = CGFloat(min(max(s.fontSize, ToolSettings.fontSizeRange.lowerBound), ToolSettings.fontSizeRange.upperBound))
        var font = NSFont(name: s.fontName, size: size) ?? NSFont.systemFont(ofSize: size)
        let fm = NSFontManager.shared
        font = fm.convert(font, toHaveTrait: s.bold ? .boldFontMask : .unboldFontMask)
        font = fm.convert(font, toHaveTrait: s.italic ? .italicFontMask : .unitalicFontMask)
        return font
    }

    static func attributes(for s: ToolSettings) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.alignment = s.textAlignment.nsAlignment
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font(for: s),
            .foregroundColor: s.primaryColor,
            .paragraphStyle: para,
            // Always present so toggling underline off clears it from existing text.
            .underlineStyle: s.underline ? NSUnderlineStyle.single.rawValue : 0,
        ]
        return attrs
    }

    /// Called (via observation) whenever any text option or the primary colour changes.
    private func settingsDidChange() {
        guard let context else {
            // Still read the options so observation keeps tracking while inactive.
            _ = Self.attributes(for: ToolSettings.shared)
            return
        }
        let attrs = Self.attributes(for: context.settings)
        applyAttributes(attrs)
    }

    private func applyAttributes(_ attrs: [NSAttributedString.Key: Any]) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        // Never touch the storage while the IME is composing; re-apply when composition ends.
        if tv.hasMarkedText() { needsReapply = true; return }
        needsReapply = false
        storage.beginEditing()
        storage.addAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        tv.typingAttributes = attrs
        if let font = attrs[.font] as? NSFont { NSFontManager.shared.setSelectedFont(font, isMultiple: false) }
        growToFit()
    }

    private func textDidChange() {
        if needsReapply, let context { applyAttributes(Self.attributes(for: context.settings)) }
        growToFit()
    }

    /// The font panel changed the font: mirror it into the tool options (which then update the text).
    private func fontPanelDidChange(_ font: NSFont) {
        guard let s = context?.settings else { return }
        let traits = NSFontManager.shared.traits(of: font)
        s.fontName = font.fontName
        s.fontSize = min(max(Double(font.pointSize), ToolSettings.fontSizeRange.lowerBound), ToolSettings.fontSizeRange.upperBound)
        s.bold = traits.contains(.boldFontMask)
        s.italic = traits.contains(.italicFontMask)
    }

    /// Grows the box height when the text needs more room (width never changes automatically).
    private func growToFit() {
        guard let tv = textView, let box, let storage = tv.textStorage else { return }
        let needed = TextRenderer.requiredHeight(for: storage, boxWidth: box.width)
        if needed > box.height + 0.5 { setBox(CGRect(x: box.minX, y: box.minY, width: box.width, height: needed)) }
    }

    // MARK: - Geometry

    private func pad(_ m: CGFloat) -> CGFloat { 4 / m }

    private func handlePoint(_ h: Handle, in r: CGRect) -> CGPoint {
        switch h {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .top: CGPoint(x: r.midX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .right: CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        case .left: CGPoint(x: r.minX, y: r.midY)
        }
    }

    private func handle(at p: CGPoint, magnification m: CGFloat) -> Handle? {
        guard let box else { return nil }
        let frame = box.insetBy(dx: -pad(m), dy: -pad(m))
        let tol = 7 / m
        return Handle.allCases.first {
            let h = handlePoint($0, in: frame)
            return abs(h.x - p.x) <= tol && abs(h.y - p.y) <= tol
        }
    }

    /// The border band: just outside the box and a few pixels inside its edge.
    private func isBorder(_ p: CGPoint, magnification m: CGFloat) -> Bool {
        guard let box else { return false }
        if handle(at: p, magnification: m) != nil { return true }
        return box.insetBy(dx: -10 / m, dy: -10 / m).contains(p) && !box.insetBy(dx: 4 / m, dy: 4 / m).contains(p)
    }

    private func setBox(_ new: CGRect) {
        guard let old = box, let context else { return }
        box = new
        textView?.frame = new
        let m = context.magnification
        context.setNeedsOverlayDisplay(old.union(new).insetBy(dx: -16 / m, dy: -16 / m))
    }

    private func resized(_ original: CGRect, handle h: Handle, to p: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        switch h {
        case .topLeft: minX = p.x; minY = p.y
        case .top: minY = p.y
        case .topRight: maxX = p.x; minY = p.y
        case .right: maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom: maxY = p.y
        case .bottomLeft: minX = p.x; maxY = p.y
        case .left: minX = p.x
        }
        if maxX - minX < Self.minSize.width { if minX != original.minX { minX = maxX - Self.minSize.width } else { maxX = minX + Self.minSize.width } }
        if maxY - minY < Self.minSize.height { if minY != original.minY { minY = maxY - Self.minSize.height } else { maxY = minY + Self.minSize.height } }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Mouse

    func mouseDown(_ event: ToolEvent, context: ToolContext) {
        self.context = context
        let p = event.location
        let m = context.magnification
        if box != nil, textView != nil {
            if let h = handle(at: p, magnification: m), let box { gesture = .resizing(h, original: box); return }
            if isBorder(p, magnification: m), let box {
                gesture = .moving(grab: CGSize(width: p.x - box.minX, height: p.y - box.minY))
                return
            }
            // Click outside the box: commit it, then start a new one here.
            guard commit(force: true) else { return }
        }
        guard context.canvas.bounds.contains(p) else { return }
        guard context.canvas.activeLayer?.isVisible == true else { NSSound.beep(); return }
        gesture = .creating(start: p)
        dragRect = CGRect(origin: p, size: .zero)
    }

    func mouseDragged(_ event: ToolEvent, context: ToolContext) {
        let p = event.location
        switch gesture {
        case .none:
            break
        case .creating(let start):
            let old = dragRect ?? .null
            let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
                .intersection(context.canvas.bounds)
            dragRect = r
            let m = context.magnification
            context.setNeedsOverlayDisplay(old.union(r).insetBy(dx: -4 / m, dy: -4 / m))
        case .moving(let grab):
            guard let box else { return }
            setBox(CGRect(x: (p.x - grab.width).rounded(), y: (p.y - grab.height).rounded(), width: box.width, height: box.height))
        case .resizing(let h, let original):
            var r = resized(original, handle: h, to: p)
            r = CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
            setBox(r)
        }
    }

    func mouseUp(_ event: ToolEvent, context: ToolContext) {
        defer { gesture = .none }
        switch gesture {
        case .none:
            break
        case .creating(let start):
            let drag = dragRect ?? .zero
            dragRect = nil
            let canvasBounds = context.canvas.bounds
            let size = CGFloat(context.settings.fontSize)
            var r: CGRect
            if drag.width < 6 && drag.height < 6 {
                // Plain click: default box starting at the click, extending right.
                let w = min(max(size * 8, 120), max(Self.minSize.width, canvasBounds.maxX - start.x))
                r = CGRect(x: start.x, y: start.y, width: w, height: ceil(size * 1.3) + 2 * TextLayoutMetrics.inset.height)
            } else {
                r = drag
            }
            r.size.width = max(r.width, Self.minSize.width)
            r.size.height = max(r.height, ceil(size * 1.3) + 2 * TextLayoutMetrics.inset.height)
            r = CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
            beginEditing(in: r, context: context)
        case .moving, .resizing:
            // Return keyboard focus to the text view (CanvasView took it on mouseDown).
            if let tv = textView { tv.window?.makeFirstResponder(tv) }
        }
        context.setNeedsOverlayDisplay()
    }

    func mouseMoved(_ event: ToolEvent, context: ToolContext) {
        guard box != nil, textView != nil else { return }
        let m = context.magnification
        if let h = handle(at: event.location, magnification: m) {
            switch h {
            case .top, .bottom: NSCursor.resizeUpDown.set()
            case .left, .right: NSCursor.resizeLeftRight.set()
            default: NSCursor.crosshair.set()
            }
        } else if isBorder(event.location, magnification: m) {
            NSCursor.openHand.set()
        }
    }

    func keyDown(_ event: NSEvent, context: ToolContext) -> Bool { false }

    // MARK: - Editing

    /// Creates the text view for `rect` and makes it first responder immediately, so the first
    /// character typed (including IME composition) goes into it.
    func beginEditing(in rect: CGRect, context: ToolContext) {
        context.canvas.commitFloatingIfNeeded()
        let tv = EditorTextView(frame: rect)
        let attrs = Self.attributes(for: context.settings)
        tv.typingAttributes = attrs
        tv.isBorderPoint = { [weak self, weak context] p in
            guard let self, let context else { return false }
            return self.isBorder(p, magnification: context.magnification)
        }
        tv.onCommit = { [weak self] in self?.commit(force: false) }
        tv.onCancel = { [weak self] in self?.discard() }
        tv.onChange = { [weak self] in self?.textDidChange() }
        tv.onFontPanelChange = { [weak self] in self?.fontPanelDidChange($0) }
        box = rect
        textView = tv
        context.view.addSubview(tv)
        tv.window?.makeFirstResponder(tv)
        NSFontManager.shared.setSelectedFont(Self.font(for: context.settings), isMultiple: false)
        context.setNeedsOverlayDisplay()
    }

    /// Escape: drops the uncommitted text.
    func discard() {
        tearDown()
    }

    /// Renders the text into the active layer (one undo step) and closes the box.
    /// - Parameter force: confirm any IME composition first. Without it, nothing happens while
    ///   marked text exists (keys belong to the IME).
    /// - Returns: false if the commit could not happen (the box stays open).
    @discardableResult
    func commit(force: Bool) -> Bool {
        guard let tv = textView, let box, let context else { return true }
        if tv.hasMarkedText() {
            guard force else { return false }
            tv.unmarkText()
        }
        let text = NSAttributedString(attributedString: tv.textStorage ?? NSTextStorage())
        if text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tearDown()
            return true
        }
        let canvas = context.canvas
        guard let layer = canvas.activeLayer, layer.isVisible else {
            NSSound.beep()
            return false
        }
        let selectionPath = canvas.selection?.path
        canvas.applyRegionEdit(layerID: layer.id, rect: box, actionName: String(localized: "Text", table: "Paint")) { ctx in
            if let selectionPath { ctx.addPath(selectionPath); ctx.clip() }
            TextRenderer.draw(text, in: box, into: ctx)
        }
        tearDown()
        return true
    }

    private func tearDown() {
        let old = box
        let tv = textView
        let wasFirst = tv.map { $0.window?.firstResponder === $0 } ?? false
        textView = nil
        box = nil
        gesture = .none
        dragRect = nil
        if let tv {
            tv.onCommit = nil; tv.onCancel = nil; tv.onChange = nil; tv.onFontPanelChange = nil; tv.isBorderPoint = nil
            tv.undoManager?.removeAllActions()
            if wasFirst { tv.window?.makeFirstResponder(context?.view) }
            tv.removeFromSuperview()
        }
        if let context, let old {
            let m = context.magnification
            context.setNeedsOverlayDisplay(old.insetBy(dx: -16 / m, dy: -16 / m))
        }
    }

    // MARK: - Overlay

    func drawOverlay(in ctx: CGContext, context: ToolContext) {
        let m = context.magnification
        let lw = 1 / m
        func dashed(_ r: CGRect) {
            ctx.setLineWidth(lw)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.stroke(r)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineDash(phase: 0, lengths: [4 * lw, 4 * lw])
            ctx.stroke(r)
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if let dragRect, case .creating = gesture { dashed(dragRect) }
        guard let box, textView != nil else { return }
        let frame = box.insetBy(dx: -pad(m), dy: -pad(m))
        dashed(frame)
        let s = 6 / m
        for h in Handle.allCases {
            let c = handlePoint(h, in: frame)
            let r = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(lw)
            ctx.stroke(r)
        }
    }
}
