import CoreGraphics
import Foundation

/// Whole-image edits (rotate, flip, resize, canvas size) applied to every layer.
extension CanvasModel {

    enum EditError: Error {
        case invalidSize
        case allocationFailed
        case canvasChanged
    }

    /// Applies `edit` to all layers as one undo step. Pixel work runs off the main thread on
    /// copies of the layer images; the new buffers are installed on the main actor.
    ///
    /// - Parameter background: colour for area added to the bottom layer by a canvas size increase.
    /// - Parameter clearSelection: drop the selection as part of the same undo step (crop).
    func apply(_ edit: ImageEdit, actionName: String, background: CGColor? = nil, clearSelection: Bool = false) async throws {
        commitFloatingIfNeeded()
        cancelLivePreview()
        let out = edit.outputSize(width: width, height: height)
        guard ImageResampler.isValidSize(width: out.width, height: out.height) else { throw EditError.invalidSize }

        // Snapshot the inputs: ids + revisions detect edits made while the task runs.
        let stamp = layers.map { ($0.id, $0.contentRevision) }
        var inputs: [CGImage] = []
        for layer in layers {
            guard let image = layer.buffer.copyImage() else { throw EditError.allocationFailed }
            inputs.append(image)
        }
        let oldWidth = width, oldHeight = height
        let results = try await Task.detached(priority: .userInitiated) { () -> [CGImage] in
            var outputs: [CGImage] = []
            outputs.reserveCapacity(inputs.count)
            for (i, image) in inputs.enumerated() {
                guard let result = ImageResampler.apply(edit, to: image, fill: i == 0 ? background : nil) else {
                    throw EditError.allocationFailed
                }
                outputs.append(result)
            }
            return outputs
        }.value

        // Anything floating or previewed while the task ran is merged first: it bumps the layer's
        // revision, so the check below rejects the stale result instead of silently losing it.
        commitFloatingIfNeeded()
        cancelLivePreview()
        guard width == oldWidth, height == oldHeight, layers.count == stamp.count,
              zip(layers, stamp).allSatisfy({ $0.id == $1.0 && $0.contentRevision == $1.1 })
        else { throw EditError.canvasChanged }

        var buffers: [RasterBuffer] = []
        for image in results {
            guard let b = RasterBuffer(image: image, colorSpace: colorSpace) else { throw EditError.allocationFailed }
            buffers.append(b)
        }
        let newSelection = Self.transform(selection, for: edit, oldWidth: oldWidth, oldHeight: oldHeight)
        performStructuralEdit(actionName: actionName) { m in
            for (layer, buffer) in zip(m.layers, buffers) {
                layer.buffer = buffer
                layer.contentRevision &+= 1
            }
            m.replaceLayers(m.layers, width: out.width, height: out.height)
            m.setSelection(clearSelection ? nil : newSelection, undoable: false)
        }
    }

    /// Selection after `edit`: moved with the pixels, or dropped when it no longer makes sense.
    static func transform(_ selection: CanvasSelection?, for edit: ImageEdit, oldWidth w: Int, oldHeight h: Int) -> CanvasSelection? {
        guard let selection else { return nil }
        let W = CGFloat(w), H = CGFloat(h)
        let t: CGAffineTransform
        switch edit {
        case .rotateRight: t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: H, ty: 0)
        case .rotateLeft: t = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: W)
        case .rotate180: t = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: W, ty: H)
        case .flipHorizontal: t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: W, ty: 0)
        case .flipVertical: t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: H)
        case .resize(let nw, let nh, _): t = CGAffineTransform(scaleX: CGFloat(nw) / W, y: CGFloat(nh) / H)
        case .canvasSize(_, _, let ox, let oy): t = CGAffineTransform(translationX: CGFloat(ox), y: CGFloat(oy))
        }
        var tt = t
        guard let path = selection.path.copy(using: &tt) else { return nil }
        let result = CanvasSelection(path: path)
        let newSize = edit.outputSize(width: w, height: h)
        let canvas = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        return result.bounds.intersects(canvas) ? result : nil
    }
}
