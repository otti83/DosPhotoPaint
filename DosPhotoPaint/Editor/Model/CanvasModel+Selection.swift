import AppKit

enum CanvasEditError: Error { case allocationFailed }

enum FloatEnd { case commit, delete, cancel }

/// Selection helpers: lifting pixels into floating content, committing / cancelling it,
/// clearing, cropping and expanding.
///
/// Undo design for "lift + move + commit": exactly one undo action is registered, when the
/// content starts floating (target = the `FloatSession`). Undone mid-float it cancels the float;
/// after the commit it restores the exact pre-lift pixels of (source rect ∪ destination rect)
/// and the original selection, and registers the redo. Pressing Escape removes the action again
/// (nothing happened). No undo group is ever left open across events.
extension CanvasModel {

    // MARK: - Pixels

    /// Pixels of the active-layer region under `selection` (outside a free-form path they are
    /// transparent) and the integral rect they came from.
    func selectionPixels(of layer: Layer, in sel: CanvasSelection) -> (image: CGImage, rect: CGRect)? {
        let rect = layer.buffer.clamp(sel.bounds)
        guard !rect.isNull,
              let buf = RasterBuffer(width: Int(rect.width), height: Int(rect.height), colorSpace: layer.buffer.colorSpace)
        else { return nil }
        let ctx = buf.context
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.addPath(sel.path)
        ctx.clip()
        _ = layer.buffer.withImage(in: rect) { ctx.drawUpright($0, in: rect) }
        ctx.restoreGState()
        guard let image = buf.copyImage() else { return nil }
        return (image, rect)
    }

    /// `image` with every opaque pixel equal to `color` made fully transparent.
    func makingTransparent(_ image: CGImage, matching color: NSColor) -> CGImage {
        guard let buf = RasterBuffer(image: image, colorSpace: colorSpace),
              let cg = color.usingColorSpace(.sRGB)?.cgColor.converted(to: colorSpace, intent: .defaultIntent, options: nil),
              let comps = cg.components, comps.count >= 3 else { return image }
        let r = UInt8(max(0, min(255, (comps[0] * 255).rounded())))
        let g = UInt8(max(0, min(255, (comps[1] * 255).rounded())))
        let b = UInt8(max(0, min(255, (comps[2] * 255).rounded())))
        let w = buf.width, h = buf.height
        buf.withMutablePixels { p, bpr in
            for y in 0..<h {
                let row = p + y * bpr
                for x in 0..<w {
                    let px = row + x * 4
                    if px[3] == 255, px[0] == r, px[1] == g, px[2] == b { px[0] = 0; px[1] = 0; px[2] = 0; px[3] = 0 }
                }
            }
        }
        return buf.copyImage() ?? image
    }

    /// The floating content rendered at its current transform (integral bounds, canvas pixels).
    func renderedFloatingImage() -> CGImage? {
        guard let f = floating else { return nil }
        let rect = f.bounds.integral
        guard rect.width >= 1, rect.height >= 1,
              let buf = RasterBuffer(width: Int(rect.width), height: Int(rect.height), colorSpace: colorSpace) else { return nil }
        let ctx = buf.context
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.setAlpha(f.opacity)
        ctx.interpolationQuality = .high
        ctx.concatenate(f.transform)
        ctx.drawUpright(f.image, in: CGRect(x: 0, y: 0, width: f.image.width, height: f.image.height))
        return buf.copyImage()
    }

    // MARK: - Lift / paste

    /// Lifts the selected pixels of the active layer into floating content and clears the source.
    /// `transparentColor`: pixels equal to it become transparent in the lifted image.
    @discardableResult
    func liftSelection(transparentColor: NSColor?) -> Bool {
        guard floating == nil, let sel = selection, let layer = activeLayer, layer.isVisible,
              let (pixels, rect) = selectionPixels(of: layer, in: sel),
              let before = layer.buffer.copyImage(in: rect) else { return false }
        let image = transparentColor.map { makingTransparent(pixels, matching: $0) } ?? pixels

        // Clear the source (same non-antialiased mask that was used to extract).
        let ctx = layer.buffer.context
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        ctx.addPath(sel.path)
        ctx.clip()
        ctx.clear(rect)
        ctx.restoreGState()
        layer.contentRevision &+= 1
        invalidate(rect)

        var toLocal = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
        let session = FloatSession(model: self, originalSelection: sel,
                                   localPath: sel.path.copy(using: &toLocal) ?? sel.path, liftRect: rect, before: before)
        floating = FloatingContent(layerID: layer.id, image: image,
                                   transform: CGAffineTransform(translationX: rect.minX, y: rect.minY), session: session)
        registerUndoAction(for: session, name: String(localized: "Move Selection", table: "Paint"))
        return true
    }

    /// Starts floating pasted content at `origin` (top-left, pixels).
    func beginFloatingPaste(_ image: CGImage, origin: CGPoint, layerID: UUID, transparentColor: NSColor?) {
        commitFloatingIfNeeded()
        let img = transparentColor.map { makingTransparent(image, matching: $0) } ?? image
        let local = CGPath(rect: CGRect(x: 0, y: 0, width: img.width, height: img.height), transform: nil)
        let session = FloatSession(model: self, originalSelection: selection, localPath: local, liftRect: nil, before: nil)
        var t = CGAffineTransform(translationX: origin.x, y: origin.y)
        floating = FloatingContent(layerID: layerID, image: img, transform: t, session: session)
        setSelection(CanvasSelection(path: local.copy(using: &t) ?? local), undoable: false)
        registerUndoAction(for: session, name: String(localized: "Paste", table: "Paint"))
    }

    /// Changes the floating transform; the selection outline follows.
    func setFloatingTransform(_ transform: CGAffineTransform) {
        guard var f = floating else { return }
        f.transform = transform
        floating = f
        if let s = f.session {
            var t = transform
            if let path = s.localPath.copy(using: &t) { setSelection(CanvasSelection(path: path), undoable: false) }
        }
    }

    func cancelFloating() { finishFloating(.cancel, actionName: "") }

    private func registerUndoAction(for session: FloatSession, name: String) {
        guard let um = undoManager else { return }
        // The closure retains the session: NSUndoManager does not retain its target.
        um.registerUndo(withTarget: session) { [session] _ in session.model?.undoFloat(session) }
        um.setActionName(name)
    }

    private func undoFloat(_ s: FloatSession) {
        if floating?.session === s {   // ⌘Z while still floating
            finishFloating(.cancel, actionName: "")
            return
        }
        guard let c = s.committed, let layer = layer(id: c.layerID), let current = layer.buffer.copyImage(in: c.rect) else { return }
        layer.buffer.replace(c.rect, with: c.previous)
        layer.contentRevision &+= 1
        registerRegionUndo(layerID: c.layerID, rect: c.rect, previous: current, actionName: String(localized: "Move Selection", table: "Paint"))
        setSelection(s.originalSelection, undoable: true)
        invalidate(c.rect)
    }

    /// Ends the current float. `.commit` merges it (one undo step), `.delete` discards its
    /// content for good (undo restores the source), `.cancel` restores the lifted pixels exactly.
    func finishFloating(_ end: FloatEnd, actionName: String) {
        guard let f = floating, let s = f.session else { return }
        floating = nil
        let layer = layer(id: f.layerID)

        if end == .cancel {
            // Nothing happened: drop the float's undo action (only safe outside undo/redo and
            // outside an open group; otherwise it stays as an inert step).
            if let um = undoManager, !um.isUndoing, !um.isRedoing, um.groupingLevel == 0 { um.removeAllActions(withTarget: s) }
            if let layer, let before = s.before, let rect = s.liftRect {
                layer.buffer.replace(rect, with: before)
                layer.contentRevision &+= 1
                invalidate(rect)
            }
            setSelection(s.originalSelection, undoable: false)
            return
        }

        var t = f.transform
        let finalSelection: CanvasSelection? = (end == .delete && s.liftRect == nil)
            ? s.originalSelection
            : s.localPath.copy(using: &t).map { CanvasSelection(path: $0) }

        if let layer {
            let draw = end == .commit ? f.bounds.integral.intersection(bounds) : CGRect.null
            let union = (s.liftRect ?? .null).union(draw.isNull ? .null : draw)
            if !union.isNull, !union.isEmpty, let current = layer.buffer.copyImage(in: union),
               let tmp = RasterBuffer(image: current, colorSpace: layer.buffer.colorSpace) {
                if let before = s.before, let lift = s.liftRect {
                    tmp.replace(CGRect(x: lift.minX - union.minX, y: lift.minY - union.minY, width: lift.width, height: lift.height), with: before)
                }
                if let previous = tmp.copyImage() {
                    if !draw.isNull {
                        let ctx = layer.buffer.context
                        ctx.saveGState()
                        ctx.setAlpha(f.opacity)
                        let pure = t.a == 1 && t.b == 0 && t.c == 0 && t.d == 1 && t.tx == t.tx.rounded() && t.ty == t.ty.rounded()
                        ctx.interpolationQuality = pure ? .none : .high
                        ctx.concatenate(t)
                        ctx.drawUpright(f.image, in: CGRect(x: 0, y: 0, width: f.image.width, height: f.image.height))
                        ctx.restoreGState()
                    }
                    layer.contentRevision &+= 1
                    s.committed = FloatSession.Committed(layerID: layer.id, rect: union, previous: previous)
                    invalidate(union)
                }
            }
        }
        setSelection(finalSelection, undoable: false)   // restored by `undoFloat`
    }

    // MARK: - Clear

    /// Clears the selected pixels of the active layer to transparent (or discards the floating
    /// content). One undo step.
    @discardableResult
    func deleteSelectionContents(actionName: String) -> Bool {
        if let f = floating, let s = f.session {
            // Pasted content that was never lifted simply disappears.
            finishFloating(s.liftRect == nil ? .cancel : .delete, actionName: actionName)
            return true
        }
        guard let sel = selection, let layer = activeLayer else { return false }
        let rect = layer.buffer.clamp(sel.bounds)
        guard !rect.isNull else { return false }
        applyRegionEdit(layerID: layer.id, rect: rect, actionName: actionName) { ctx in
            ctx.setShouldAntialias(false)
            ctx.addPath(sel.path)
            ctx.clip()
            ctx.clear(rect)
        }
        return true
    }

    // MARK: - Crop / expand

    /// The integral, canvas-clamped crop rectangle, or nil when cropping to `rect` would be a no-op.
    func cropRect(for rect: CGRect) -> CGRect? {
        let r = rect.integral.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1, r.size != size else { return nil }
        return r
    }

    /// Crops every layer to `rect` (clamped to the canvas). One undo step. Clears the selection.
    @discardableResult
    func crop(to rect: CGRect, actionName: String = String(localized: "Crop", table: "Paint")) -> Bool {
        guard let r = cropRect(for: rect) else { return false }
        do {
            try performStructuralEdit(actionName: actionName) { m in
                for layer in m.layers {
                    guard let nb = RasterBuffer(width: Int(r.width), height: Int(r.height), colorSpace: layer.buffer.colorSpace)
                    else { throw CanvasEditError.allocationFailed }
                    _ = layer.buffer.withImage(in: r) { nb.replace(nb.bounds, with: $0) }
                    layer.buffer = nb
                    layer.contentRevision &+= 1
                }
                m.replaceLayers(m.layers, width: Int(r.width), height: Int(r.height))
                m.setSelection(nil, undoable: false)
            }
            return true
        } catch {
            return false
        }
    }

    /// Grows the canvas to at least `width × height`, anchored top-left. The bottom layer's new
    /// area is filled with `background` (transparent if nil); other layers get transparency.
    @discardableResult
    func expandCanvas(toWidth width: Int, height: Int, background: CGColor?) -> Bool {
        let w = max(width, self.width), h = max(height, self.height)
        guard w != self.width || h != self.height, ImageResampler.isValidSize(width: w, height: h) else { return false }
        do {
            try performStructuralEdit(actionName: String(localized: "Expand Canvas", table: "Paint")) { m in
                for (i, layer) in m.layers.enumerated() {
                    guard let nb = RasterBuffer(width: w, height: h, colorSpace: layer.buffer.colorSpace)
                    else { throw CanvasEditError.allocationFailed }
                    if i == 0, let background { nb.fill(background) }
                    _ = layer.buffer.withImage { nb.replace(CGRect(x: 0, y: 0, width: m.width, height: m.height), with: $0) }
                    layer.buffer = nb
                    layer.contentRevision &+= 1
                }
                m.replaceLayers(m.layers, width: w, height: h)
            }
            return true
        } catch {
            return false
        }
    }

    /// Adds an empty layer above the active one and makes it active (structural undo step).
    @discardableResult
    func addEmptyLayerAboveActive(name: String) -> Bool {
        guard let buffer = RasterBuffer(width: width, height: height, colorSpace: colorSpace) else { return false }
        performStructuralEdit(actionName: String(localized: "Paste as New Layer", table: "Paint")) { m in
            let layer = Layer(name: name, buffer: buffer)
            m.insertLayer(layer, at: (m.activeLayerIndex ?? m.layers.count - 1) + 1)
            m.activeLayerID = layer.id
        }
        return true
    }
}
