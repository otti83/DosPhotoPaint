import AppKit

/// Paint bucket. Flood-fills from the clicked pixel of the ACTIVE layer.
///
/// Design: the similarity test samples the active layer only (like MS Paint), not the visible
/// composite, so filling is predictable on multi-layer documents. The fill is computed on the
/// whole layer and clipped to the selection when painting (a click outside the selection does
/// nothing). Large layers are processed on a background task from a copy of the pixels.
final class FillTool: CanvasTool {
    let kind = ToolKind.fill
    /// Layers above this many pixels are filled off the main thread.
    static let backgroundThresholdPixels = 4_000_000
    private var isRunning = false

    func mouseDown(_ event: ToolEvent, context: ToolContext) {
        guard !isRunning else { return }
        let canvas = context.canvas
        guard let layer = canvas.activeLayer else { return }
        guard layer.isVisible else { NSSound.beep(); return }
        let x = Int(floor(event.location.x)), y = Int(floor(event.location.y))
        guard x >= 0, y >= 0, x < canvas.width, y < canvas.height else { return }
        if let sel = canvas.selection, !sel.path.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) { return }
        canvas.commitFloatingIfNeeded()

        let s = context.settings
        let options = FloodFill.Options(tolerance: Int(s.fillTolerance.rounded()), contiguous: s.fillContiguous, edgeBlend: true)
        guard let bitmap = Self.snapshot(layer.buffer) else { return }
        let layerID = layer.id
        let revision = layer.contentRevision
        let buffer = layer.buffer
        let color = Self.components(of: s.primaryColor, in: layer.buffer.colorSpace)
        let opacity = s.opacity * Double(s.primaryColor.usingColorSpace(.sRGB)?.alphaComponent ?? 1)

        if bitmap.width * bitmap.height <= Self.backgroundThresholdPixels {
            guard let result = FloodFill.fill(bitmap, seedX: x, seedY: y, options: options) else { return }
            Self.apply(result, canvas: canvas, layerID: layerID, color: color, opacity: opacity)
            return
        }

        isRunning = true
        Task { @MainActor [weak self, weak canvas] in
            let result = await Task.detached(priority: .userInitiated) {
                FloodFill.fill(bitmap, seedX: x, seedY: y, options: options)
            }.value
            self?.isRunning = false
            guard let canvas else { return }
            // The layer must be exactly as it was when the fill started; otherwise the mask is stale.
            guard let layer = canvas.layer(id: layerID), layer.buffer === buffer, layer.contentRevision == revision else {
                NSSound.beep(); return
            }
            if let result { Self.apply(result, canvas: canvas, layerID: layerID, color: color, opacity: opacity) }
        }
    }

    func cursor(context: ToolContext) -> NSCursor { .crosshair }

    // MARK: - Helpers

    private static func snapshot(_ buffer: RasterBuffer) -> FloodFill.Bitmap? {
        let bpr = buffer.bytesPerRow, h = buffer.height
        return buffer.withMutablePixels { base, _ in
            FloodFill.Bitmap(data: Array(UnsafeBufferPointer(start: base, count: bpr * h)),
                             width: buffer.width, height: h, bytesPerRow: bpr)
        }
    }

    /// Straight RGB components of `color` in the layer's colour space.
    private static func components(of color: NSColor, in space: CGColorSpace) -> [CGFloat] {
        let cg = color.usingColorSpace(.sRGB)?.cgColor ?? NSColor.black.cgColor
        if let c = cg.converted(to: space, intent: .defaultIntent, options: nil)?.components, c.count >= 4 {
            return Array(c.prefix(3))
        }
        return Array((cg.components ?? [0, 0, 0, 1]).prefix(3))
    }

    private static func apply(_ result: FloodFill.Result, canvas: CanvasModel, layerID: UUID, color: [CGFloat], opacity: Double) {
        let rect = result.bounds
        let rw = Int(rect.width), rh = Int(rect.height), x0 = Int(rect.minX), y0 = Int(rect.minY)
        guard rw > 0, rh > 0, let layer = canvas.layer(id: layerID) else { return }
        // Premultiplied RGBA covering the region; coverage is the alpha.
        // One premultiplied pixel per coverage value (256 entries) instead of float math per pixel:
        // keeps large fills (tens of megapixels) off the slow path on the main thread.
        var lut = [UInt8](repeating: 0, count: 256 * 4)
        for cov in 0..<256 {
            let f = CGFloat(cov) / 255
            for c in 0..<3 { lut[cov * 4 + c] = UInt8(max(0, min(255, (color[c] * f * 255).rounded()))) }
            lut[cov * 4 + 3] = UInt8(cov)
        }
        var data = Data(count: rw * rh * 4)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt8.self)
            result.mask.withUnsafeBufferPointer { mask in
                lut.withUnsafeBufferPointer { l in
                    for row in 0..<rh {
                        let src = (y0 + row) * result.width + x0
                        let dst = row * rw * 4
                        for col in 0..<rw {
                            let k = Int(mask[src + col]) * 4
                            let o = dst + col * 4
                            out[o] = l[k]; out[o + 1] = l[k + 1]; out[o + 2] = l[k + 2]; out[o + 3] = l[k + 3]
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: rw, height: rh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rw * 4,
                                  space: layer.buffer.colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return }
        let selection = canvas.selection
        canvas.applyRegionEdit(layerID: layerID, rect: rect, actionName: String(localized: "Fill", table: "Paint")) { ctx in
            if let selection { ctx.addPath(selection.path); ctx.clip() }
            ctx.setAlpha(opacity)
            ctx.interpolationQuality = .none
            ctx.drawUpright(image, in: rect)
        }
    }
}
