import CoreGraphics

/// Composites layers (plus the live tool preview and floating selection) for a dirty rect.
enum CanvasRenderer {
    /// Recomposites `rect` of `target` from the model's visible layers.
    static func composite(model: CanvasModel, into target: RasterBuffer, rect: CGRect) {
        let r = target.clamp(rect)
        guard !r.isNull else { return }
        let ctx = target.context
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.clear(r)
        drawLayers(model.layers, into: ctx, rect: r, preview: model.livePreview, floating: model.floating,
                   previewClip: model.selection?.path)
        ctx.restoreGState()
    }

    /// Draws visible layers bottom→top with normal blending and per-layer opacity.
    /// `previewClip` limits the live tool preview to the selection, so what is shown while
    /// painting is exactly what the commit will merge.
    static func drawLayers(_ layers: [Layer], into ctx: CGContext, rect r: CGRect,
                           preview: LivePreview?, floating: FloatingContent?, previewClip: CGPath? = nil) {
        ctx.interpolationQuality = .none
        for layer in layers where layer.isVisible && layer.opacity > 0 {
            let hasPreview = preview.map { $0.layerID == layer.id && $0.dirtyRect.intersects(r) } ?? false
            let hasFloating = floating.map { $0.layerID == layer.id && $0.bounds.intersects(r) } ?? false
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            if hasPreview || hasFloating {
                // Isolate the layer so stroke opacity / eraser act on this layer only and the
                // layer opacity is applied once to the combined result.
                ctx.beginTransparencyLayer(in: r, auxiliaryInfo: nil)
                _ = layer.buffer.withImage(in: r) { ctx.drawUpright($0, in: r) }
                if let floating, hasFloating {
                    ctx.saveGState()
                    ctx.setAlpha(floating.opacity)
                    ctx.interpolationQuality = .high
                    ctx.concatenate(floating.transform)
                    let ir = CGRect(x: 0, y: 0, width: floating.image.width, height: floating.image.height)
                    ctx.drawUpright(floating.image, in: ir)
                    ctx.restoreGState()
                }
                if let preview, hasPreview {
                    ctx.saveGState()
                    if let previewClip { ctx.addPath(previewClip); ctx.clip() }
                    ctx.setAlpha(preview.opacity)
                    ctx.setBlendMode(preview.blendMode)
                    _ = preview.buffer.withImage(in: r) { ctx.drawUpright($0, in: r) }
                    ctx.restoreGState()
                }
                ctx.endTransparencyLayer()
            } else {
                _ = layer.buffer.withImage(in: r) { ctx.drawUpright($0, in: r) }
            }
            ctx.restoreGState()
        }
    }
}
