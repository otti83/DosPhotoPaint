import CoreGraphics
import Foundation
import Observation

/// The editable raster document: layers, selection, composite cache and undo plumbing.
///
/// All coordinates are y-down pixel coordinates. Views are notified through
/// `onInvalidate(pixelRect)` so that only the changed region is re-composited and redrawn.
@Observable
final class CanvasModel {
    private(set) var width: Int
    private(set) var height: Int
    let colorSpace: CGColorSpace
    /// Bottom → top.
    private(set) var layers: [Layer]
    var activeLayerID: UUID
    private(set) var selection: CanvasSelection?
    /// Pixels being moved/transformed or pasted, not yet merged into a layer.
    var floating: FloatingContent? {
        didSet { invalidate(union(oldValue?.bounds, floating?.bounds)) }
    }

    @ObservationIgnored var livePreview: LivePreview?
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Called with the pixel rect that must be redrawn (`.infinite` = everything).
    @ObservationIgnored var onInvalidate: ((CGRect) -> Void)?
    /// Called after the canvas size changed (view must resize).
    @ObservationIgnored var onSizeChange: (() -> Void)?
    /// Called after the selection changed (view redraws overlay).
    @ObservationIgnored var onSelectionChange: (() -> Void)?

    @ObservationIgnored private(set) var composite: RasterBuffer
    @ObservationIgnored private var compositeDirty: CGRect = .null
    @ObservationIgnored private var scratch: RasterBuffer?
    /// Diagnostics: cumulative bytes of pixel data handed to region undo (read by PerformanceTests).
    @ObservationIgnored private(set) var regionUndoBytesRegistered = 0
    /// Edge length of the tiles a stroke's undo data is split into (see `commitLivePreview`).
    static let undoTileSize = 128
    /// Tiles (index = row * columns + column) touched by the current live preview.
    @ObservationIgnored private var previewTiles = Set<Int>()

    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    var size: CGSize { CGSize(width: width, height: height) }
    var activeLayer: Layer? { layers.first { $0.id == activeLayerID } }
    var activeLayerIndex: Int? { layers.firstIndex { $0.id == activeLayerID } }

    // MARK: - Init

    /// New canvas with a background layer. `background == nil` → transparent.
    init?(width: Int, height: Int, colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!, background: CGColor?) {
        guard let buffer = RasterBuffer(width: width, height: height, colorSpace: colorSpace),
              let comp = RasterBuffer(width: width, height: height, colorSpace: buffer.colorSpace) else { return nil }
        if let background { buffer.fill(background) }
        let layer = Layer(name: Self.backgroundLayerName, buffer: buffer)
        self.width = width
        self.height = height
        self.colorSpace = buffer.colorSpace
        self.layers = [layer]
        self.activeLayerID = layer.id
        self.composite = comp
        compositeDirty = bounds
    }

    /// Canvas holding `image` as its single background layer, in the image's colour space.
    convenience init?(image: CGImage) {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        self.init(width: image.width, height: image.height, colorSpace: space, background: nil)
        layers[0].buffer.replace(bounds, with: image)
        compositeDirty = bounds
    }

    /// Canvas rebuilt from stored layers (project files). Layers must all match `width × height`.
    init?(width: Int, height: Int, colorSpace: CGColorSpace, layers: [Layer], activeLayerID: UUID?) {
        guard !layers.isEmpty, layers.allSatisfy({ $0.buffer.width == width && $0.buffer.height == height }),
              let comp = RasterBuffer(width: width, height: height, colorSpace: colorSpace) else { return nil }
        self.width = width
        self.height = height
        self.colorSpace = comp.colorSpace
        self.layers = layers
        self.activeLayerID = activeLayerID.flatMap { id in layers.contains { $0.id == id } ? id : nil } ?? layers.last!.id
        self.composite = comp
        compositeDirty = bounds
    }

    static var backgroundLayerName: String { String(localized: "Background", table: "Paint") }

    func layer(id: UUID) -> Layer? { layers.first { $0.id == id } }

    // MARK: - Invalidation & compositing

    func invalidate(_ rect: CGRect) {
        guard !rect.isNull, !rect.isEmpty else { return }
        let r = rect.isInfinite ? bounds : rect.integral.intersection(bounds)
        guard !r.isNull, !r.isEmpty else { return }
        compositeDirty = compositeDirty.union(r)
        onInvalidate?(r)
    }

    func invalidateAll() { invalidate(bounds) }

    /// Brings the composite cache up to date for the dirty region.
    func updateComposite() {
        guard !compositeDirty.isNull else { return }
        CanvasRenderer.composite(model: self, into: composite, rect: compositeDirty)
        compositeDirty = .null
    }

    /// Copy of the merged visible image (transparent where nothing is painted).
    func compositeImage(in rect: CGRect? = nil) -> CGImage? {
        updateComposite()
        return composite.copyImage(in: rect)
    }

    /// Merged image of the visible layers, excluding live previews/floating content,
    /// optionally over an opaque background colour (for formats without alpha).
    func flattenedImage(background: CGColor? = nil) -> CGImage? {
        guard let out = RasterBuffer(width: width, height: height, colorSpace: colorSpace) else { return nil }
        if let background { out.fill(background) }
        CanvasRenderer.drawLayers(layers, into: out.context, rect: bounds, preview: nil, floating: nil)
        return out.copyImage()
    }

    private func union(_ a: CGRect?, _ b: CGRect?) -> CGRect {
        (a ?? .null).union(b ?? .null)
    }

    // MARK: - Live preview (tool scratch buffer)

    /// Starts a live preview on `layerID`. The scratch buffer is reused between gestures.
    @discardableResult
    func beginLivePreview(layerID: UUID, opacity: Double, blendMode: CGBlendMode = .normal) -> RasterBuffer? {
        if scratch == nil || scratch!.width != width || scratch!.height != height {
            scratch = RasterBuffer(width: width, height: height, colorSpace: colorSpace)
        }
        guard let scratch else { return nil }
        if let old = livePreview { scratch.clear(old.dirtyRect) ; invalidate(old.dirtyRect) }
        previewTiles.removeAll()
        livePreview = LivePreview(layerID: layerID, buffer: scratch, opacity: opacity, blendMode: blendMode, dirtyRect: .null)
        return scratch
    }

    /// Records that `rect` of the preview buffer changed.
    func livePreviewDidChange(_ rect: CGRect) {
        guard livePreview != nil else { return }
        let r = rect.integral.intersection(bounds)
        guard !r.isNull, !r.isEmpty else { return }
        livePreview!.dirtyRect = livePreview!.dirtyRect.union(r)
        markPreviewTiles(r)
        invalidate(r)
    }

    private var tileColumns: Int { (width + Self.undoTileSize - 1) / Self.undoTileSize }

    private func markPreviewTiles(_ r: CGRect) {
        let t = Self.undoTileSize
        let cols = tileColumns
        let x0 = Int(r.minX) / t, x1 = (Int(r.maxX) - 1) / t
        let y0 = Int(r.minY) / t, y1 = (Int(r.maxY) - 1) / t
        for ty in y0...y1 { for tx in x0...x1 { previewTiles.insert(ty * cols + tx) } }
    }

    /// Pixel rects (clipped to the canvas) of the tiles touched by the preview.
    private func previewTileRects() -> [CGRect] {
        let t = CGFloat(Self.undoTileSize), cols = tileColumns
        return previewTiles.sorted().compactMap { index in
            let r = CGRect(x: CGFloat(index % cols) * t, y: CGFloat(index / cols) * t, width: t, height: t).intersection(bounds)
            return r.isEmpty ? nil : r
        }
    }

    /// Clears the preview buffer (e.g. a shape tool redrawing its preview each drag).
    func clearLivePreview() {
        guard let p = livePreview else { return }
        p.buffer.clear(p.dirtyRect)
        invalidate(p.dirtyRect)
        livePreview!.dirtyRect = .null
        previewTiles.removeAll()
    }

    /// Merges the preview into its layer (clipped to the selection) as one undo step.
    func commitLivePreview(actionName: String) {
        guard let p = livePreview else { return }
        livePreview = nil
        // Only tiles the preview touched can change (exact undo restores just those).
        let touched = previewTileRects()
        previewTiles.removeAll()
        var rect = p.dirtyRect.intersection(bounds)
        // Nothing can land outside the selection: no pixels change, so no (empty) undo step.
        if let sel = selection, !rect.isNull { rect = rect.intersection(sel.bounds.integral) }
        guard !rect.isNull, !rect.isEmpty, let layer = layer(id: p.layerID) else {
            p.buffer.clear(p.dirtyRect); invalidate(p.dirtyRect); return
        }
        let tiles = touched.map { $0.intersection(rect) }.filter { !$0.isNull && !$0.isEmpty }
        applyRegionEdit(layerID: layer.id, rect: rect, undoTiles: tiles, actionName: actionName) { ctx in
            if let sel = selection { ctx.addPath(sel.path); ctx.clip() }
            ctx.setAlpha(p.opacity)
            ctx.setBlendMode(p.blendMode)
            ctx.interpolationQuality = .none
            p.buffer.withImage(in: rect) { ctx.drawUpright($0, in: rect) }
        }
        p.buffer.clear(p.dirtyRect)
        invalidate(p.dirtyRect)
    }

    func cancelLivePreview() {
        guard let p = livePreview else { return }
        livePreview = nil
        previewTiles.removeAll()
        p.buffer.clear(p.dirtyRect)
        invalidate(p.dirtyRect)
    }

    // MARK: - Region undo (painting)

    /// Runs `edit` on the layer's context (y-down pixel space, state saved/restored) and
    /// registers a single undo step restoring the previous pixels of `rect`.
    ///
    /// `undoTiles` (optional) lists sub-rects of `rect` that are the only pixels `edit` can change
    /// (a stroke only touches the tiles it passed through). When they cover clearly less than
    /// `rect`, only those tiles are saved, so a long thin diagonal stroke does not retain a
    /// bounding box the size of the whole canvas. Still one undo step.
    func applyRegionEdit(layerID: UUID, rect: CGRect, undoTiles: [CGRect]? = nil, actionName: String,
                         _ edit: (CGContext) -> Void) {
        guard let layer = layer(id: layerID) else { return }
        let r = layer.buffer.clamp(rect)
        guard !r.isNull else { return }
        if let undoTiles, !undoTiles.isEmpty {
            let area = undoTiles.reduce(0) { $0 + $1.width * $1.height }
            if area < r.width * r.height * 0.6 {
                let saved = undoTiles.compactMap { t in layer.buffer.copyImage(in: t).map { (t, $0) } }
                guard saved.count == undoTiles.count else { return }
                let ctx = layer.buffer.context
                ctx.saveGState()
                edit(ctx)
                ctx.restoreGState()
                layer.contentRevision &+= 1
                registerTileUndo(layerID: layerID, tiles: saved, actionName: actionName)
                invalidate(r)
                return
            }
        }
        guard let before = layer.buffer.copyImage(in: r) else { return }
        let ctx = layer.buffer.context
        ctx.saveGState()
        edit(ctx)
        ctx.restoreGState()
        layer.contentRevision &+= 1
        registerRegionUndo(layerID: layerID, rect: r, previous: before, actionName: actionName)
        invalidate(r)
    }

    private func registerTileUndo(layerID: UUID, tiles: [(CGRect, CGImage)], actionName: String) {
        guard let um = undoManager else { return }
        regionUndoBytesRegistered += tiles.reduce(0) { $0 + $1.1.bytesPerRow * $1.1.height }
        um.registerUndo(withTarget: self) { model in
            model.swapTiles(layerID: layerID, tiles: tiles, actionName: actionName)
        }
        um.setActionName(actionName)
    }

    private func swapTiles(layerID: UUID, tiles: [(CGRect, CGImage)], actionName: String) {
        guard let layer = layer(id: layerID) else { return }
        let current = tiles.compactMap { t in layer.buffer.copyImage(in: t.0).map { (t.0, $0) } }
        guard current.count == tiles.count else { return }
        for (rect, image) in tiles { layer.buffer.replace(rect, with: image) }
        layer.contentRevision &+= 1
        registerTileUndo(layerID: layerID, tiles: current, actionName: actionName)
        invalidate(tiles.reduce(CGRect.null) { $0.union($1.0) })
    }

    /// Registers undo for pixels already changed by the caller (`previous` = old pixels of `rect`).
    func registerRegionUndo(layerID: UUID, rect: CGRect, previous: CGImage, actionName: String) {
        guard let um = undoManager else { return }
        regionUndoBytesRegistered += previous.bytesPerRow * previous.height
        um.registerUndo(withTarget: self) { model in
            model.swapRegion(layerID: layerID, rect: rect, with: previous, actionName: actionName)
        }
        um.setActionName(actionName)
    }

    private func swapRegion(layerID: UUID, rect: CGRect, with image: CGImage, actionName: String) {
        guard let layer = layer(id: layerID), let current = layer.buffer.copyImage(in: rect) else { return }
        layer.buffer.replace(rect, with: image)
        layer.contentRevision &+= 1
        registerRegionUndo(layerID: layerID, rect: rect, previous: current, actionName: actionName)
        invalidate(rect)
    }

    // MARK: - Snapshot undo (structure)

    func snapshot() -> CanvasSnapshot {
        CanvasSnapshot(
            width: width, height: height,
            layers: layers.map { LayerState(id: $0.id, name: $0.name, isVisible: $0.isVisible, opacity: $0.opacity, buffer: $0.buffer) },
            activeLayerID: activeLayerID,
            selection: selection)
    }

    /// Restores a snapshot (reusing `Layer` objects by id so observers stay attached).
    func restore(_ s: CanvasSnapshot) {
        let sizeChanged = s.width != width || s.height != height
        let existing = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
        layers = s.layers.map { st in
            let layer = existing[st.id] ?? Layer(id: st.id, name: st.name, buffer: st.buffer)
            layer.name = st.name
            layer.isVisible = st.isVisible
            layer.opacity = st.opacity
            if layer.buffer !== st.buffer { layer.buffer = st.buffer; layer.contentRevision &+= 1 }
            return layer
        }
        activeLayerID = s.activeLayerID
        width = s.width
        height = s.height
        selection = s.selection
        floating = nil
        if sizeChanged { resizeCaches() }
        compositeDirty = bounds
        if sizeChanged { onSizeChange?() }
        onSelectionChange?()
        invalidateAll()
    }

    /// Runs a structural edit as one undo step. `body` must replace layer buffers rather than
    /// mutating them in place (see `Layer`). Throwing from `body` rolls the canvas back.
    func performStructuralEdit(actionName: String, _ body: (CanvasModel) throws -> Void) rethrows {
        commitFloatingIfNeeded()
        let before = snapshot()
        do {
            try body(self)
        } catch {
            restore(before)
            throw error
        }
        registerSnapshotUndo(before, actionName: actionName)
        if width != before.width || height != before.height {
            resizeCaches()
            onSizeChange?()
        }
        invalidateAll()
    }

    private func registerSnapshotUndo(_ s: CanvasSnapshot, actionName: String) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            let current = model.snapshot()
            model.restore(s)
            model.registerSnapshotUndo(current, actionName: actionName)
        }
        um.setActionName(actionName)
    }

    private func resizeCaches() {
        if let comp = RasterBuffer(width: width, height: height, colorSpace: colorSpace) { composite = comp }
        scratch = nil
        livePreview = nil
    }

    // MARK: - Structural primitives (call inside `performStructuralEdit`)

    /// Replaces all layers and the canvas size at once (resize, crop, rotate…).
    func replaceLayers(_ newLayers: [Layer], width: Int, height: Int) {
        precondition(newLayers.allSatisfy { $0.buffer.width == width && $0.buffer.height == height })
        layers = newLayers
        self.width = width
        self.height = height
        if !layers.contains(where: { $0.id == activeLayerID }) { activeLayerID = layers.last!.id }
        if let sel = selection, !sel.bounds.intersects(bounds) { selection = nil }
    }

    func insertLayer(_ layer: Layer, at index: Int) {
        precondition(layer.buffer.width == width && layer.buffer.height == height)
        layers.insert(layer, at: min(max(index, 0), layers.count))
    }

    @discardableResult
    func removeLayer(id: UUID) -> Layer? {
        guard layers.count > 1, let i = layers.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = layers.remove(at: i)
        if activeLayerID == id { activeLayerID = layers[max(0, i - 1)].id }
        return removed
    }

    func moveLayer(id: UUID, to index: Int) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let l = layers.remove(at: i)
        layers.insert(l, at: min(max(index, 0), layers.count))
    }

    // MARK: - Selection

    /// Sets the selection. Undoable selection changes are registered as their own step.
    func setSelection(_ newValue: CanvasSelection?, undoable: Bool = true, actionName: String? = nil) {
        let old = selection
        selection = newValue
        onSelectionChange?()
        guard undoable, let um = undoManager else { return }
        um.registerUndo(withTarget: self) { model in
            model.setSelection(old, undoable: true, actionName: actionName)
        }
        um.setActionName(actionName ?? String(localized: "Selection", table: "Paint"))
    }

    /// Called before floating content is merged (lets the selection tool drop its handles).
    @ObservationIgnored var willCommitFloating: (() -> Void)?

    func commitFloatingIfNeeded() {
        if floating != nil { commitFloating() }
    }

    /// Merges the floating content into its layer as one region-undo step.
    func commitFloating(actionName: String = String(localized: "Paste", table: "Paint")) {
        guard let f = floating else { return }
        willCommitFloating?()
        if f.session != nil { finishFloating(.commit, actionName: actionName); return }
        floating = nil
        let rect = f.bounds.integral.intersection(bounds)
        guard !rect.isNull, !rect.isEmpty, layer(id: f.layerID) != nil else { return }
        applyRegionEdit(layerID: f.layerID, rect: rect, actionName: actionName) { ctx in
            ctx.setAlpha(f.opacity)
            ctx.interpolationQuality = .high
            ctx.concatenate(f.transform)
            ctx.drawUpright(f.image, in: CGRect(x: 0, y: 0, width: f.image.width, height: f.image.height))
        }
    }

    // MARK: - Queries

    /// Merged colour at a pixel (premultiplied components converted to straight RGBA 0…1).
    func compositeColor(atX x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double)? {
        updateComposite()
        guard let p = composite.pixel(x: x, y: y) else { return nil }
        let a = Double(p.a) / 255
        guard a > 0 else { return (0, 0, 0, 0) }
        return (min(Double(p.r) / 255 / a, 1), min(Double(p.g) / 255 / a, 1), min(Double(p.b) / 255 / a, 1), a)
    }

    /// Approximate memory used by pixel buffers (layers + caches), for diagnostics.
    var estimatedMemoryBytes: Int {
        layers.reduce(composite.byteCount + (scratch?.byteCount ?? 0)) { $0 + $1.buffer.byteCount }
    }
}
