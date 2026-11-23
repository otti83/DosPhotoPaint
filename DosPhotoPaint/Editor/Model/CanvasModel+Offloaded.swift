import CoreGraphics
import Foundation

/// One layer's pixels plus its compositing attributes; `Sendable` so it can cross to a background task.
nonisolated struct CompositeInput: Sendable {
    let image: CGImage
    let opacity: Double
    let isVisible: Bool
}

/// Layer compositing on plain `CGImage` values. Mirrors `CanvasRenderer.drawLayers` (same flipped
/// space, same normal blending / opacity, no interpolation) so that the result is identical to the
/// synchronous main-thread path.
nonisolated enum LayerCompositor {
    /// - Parameter base: drawn first with copy blending (an exact copy of a lower layer).
    static func composite(base: CGImage?, layers: [CompositeInput], width: Int, height: Int, colorSpace: CGColorSpace) -> CGImage? {
        guard let ctx = ImageTransforms.makeRGBAContext(width: width, height: height, colorSpace: colorSpace) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.clear(bounds)
        if let base {
            ctx.saveGState()
            ctx.setBlendMode(.copy)
            ctx.interpolationQuality = .none
            ctx.drawUpright(base, in: bounds)
            ctx.restoreGState()
        }
        ctx.interpolationQuality = .none
        for layer in layers where layer.isVisible && layer.opacity > 0 {
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            ctx.drawUpright(layer.image, in: bounds)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}

/// Structural edits whose pixel work runs off the main actor (large images). The result is
/// identical to the synchronous variants; only the pixel work moves. Inputs are copied into
/// `Sendable` images, buffers are installed inside `performStructuralEdit` on the main actor, and
/// layer revisions detect edits made while the task ran (the stale result is then discarded).
extension CanvasModel {

    /// Images above this many pixels are processed off the main actor by the UI.
    static var offloadPixelThreshold = 8_000_000

    var prefersOffloading: Bool { width * height > Self.offloadPixelThreshold }

    private struct Stamp: Equatable {
        let id: UUID
        let revision: Int
        let opacity: Double
        let isVisible: Bool
    }

    private func stamp() -> [Stamp] {
        layers.map { Stamp(id: $0.id, revision: $0.contentRevision, opacity: $0.opacity, isVisible: $0.isVisible) }
    }

    @discardableResult
    func mergeActiveLayerDownOffloaded() async -> Bool {
        commitFloatingIfNeeded()
        guard let index = activeLayerIndex, index > 0 else { return false }
        let upper = layers[index], lower = layers[index - 1]
        guard let lowerImage = lower.buffer.copyImage(), let upperImage = upper.buffer.copyImage() else { return false }
        let input = CompositeInput(image: upperImage, opacity: upper.opacity, isVisible: upper.isVisible)
        let space = lower.buffer.colorSpace
        let w = width, h = height
        let before = stamp()
        let merged = await Task.detached(priority: .userInitiated) {
            LayerCompositor.composite(base: lowerImage, layers: [input], width: w, height: h, colorSpace: space)
        }.value
        commitFloatingIfNeeded()
        guard let merged, width == w, height == h, stamp() == before,
              let buffer = RasterBuffer(image: merged, colorSpace: space) else { return false }
        performStructuralEdit(actionName: String(localized: "Merge Layer Down", table: "Paint")) { m in
            lower.buffer = buffer
            lower.contentRevision &+= 1
            m.removeLayer(id: upper.id)
            m.activeLayerID = lower.id
        }
        return true
    }

    @discardableResult
    func flattenOffloaded() async -> Bool {
        commitFloatingIfNeeded()
        guard layers.count > 1, let base = layers.first else { return false }
        var inputs: [CompositeInput] = []
        for layer in layers {
            guard let image = layer.buffer.copyImage() else { return false }
            inputs.append(CompositeInput(image: image, opacity: layer.opacity, isVisible: layer.isVisible))
        }
        let space = colorSpace
        let w = width, h = height
        let before = stamp()
        let merged = await Task.detached(priority: .userInitiated) {
            LayerCompositor.composite(base: nil, layers: inputs, width: w, height: h, colorSpace: space)
        }.value
        commitFloatingIfNeeded()
        guard let merged, width == w, height == h, stamp() == before,
              let buffer = RasterBuffer(image: merged, colorSpace: space) else { return false }
        performStructuralEdit(actionName: String(localized: "Flatten Image", table: "Paint")) { m in
            base.buffer = buffer
            base.isVisible = true
            base.opacity = 1
            base.contentRevision &+= 1
            for layer in m.layers.dropFirst() { m.removeLayer(id: layer.id) }
            m.activeLayerID = base.id
        }
        return true
    }

    /// Crop as a canvas-size edit with a negative offset (pure pixel copy), clearing the selection.
    @discardableResult
    func cropOffloaded(to rect: CGRect, actionName: String = String(localized: "Crop", table: "Paint")) async -> Bool {
        commitFloatingIfNeeded()
        guard let r = cropRect(for: rect) else { return false }
        do {
            try await apply(.canvasSize(width: Int(r.width), height: Int(r.height), offsetX: -Int(r.minX), offsetY: -Int(r.minY)),
                            actionName: actionName, clearSelection: true)
            return true
        } catch {
            return false
        }
    }
}
