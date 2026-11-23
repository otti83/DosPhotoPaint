import CoreGraphics
import Foundation

/// Smart Edit operations (subject cut-out, auto enhance). The analysis runs off the main thread
/// on copies of the pixels; the result is installed as one structural undo step. Like
/// `apply(_:actionName:)`, an edit made to the canvas while the task ran rejects the stale result.
extension CanvasModel {

    /// What the user sees, over white: the input Vision analyses (transparent areas would
    /// otherwise read as black).
    private func analysisImage() -> CGImage? {
        flattenedImage(background: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    }

    private struct Stamp {
        let width: Int, height: Int
        let revisions: [(UUID, Int)]
    }

    private func stamp() -> Stamp {
        Stamp(width: width, height: height, revisions: layers.map { ($0.id, $0.contentRevision) })
    }

    private func isUnchanged(since s: Stamp) -> Bool {
        width == s.width && height == s.height && layers.count == s.revisions.count
            && zip(layers, s.revisions).allSatisfy { $0.id == $1.0 && $0.contentRevision == $1.1 }
    }

    /// Makes everything outside the detected subject(s) transparent on the active layer.
    func removeBackground(actionName: String) async throws {
        commitFloatingIfNeeded()
        cancelLivePreview()
        guard let layer = activeLayer, let source = layer.buffer.copyImage(), let analysis = analysisImage() else {
            throw EditError.allocationFailed
        }
        let before = stamp(), layerID = layer.id, space = colorSpace
        let result = try await Task.detached(priority: .userInitiated) {
            let mask = try SmartImageOps.subjectMask(of: analysis)
            return try SmartImageOps.applying(mask, to: source, colorSpace: space)
        }.value
        try install(result, onLayer: layerID, since: before, actionName: actionName)
    }

    /// Copies the visible subject(s) onto a new layer above the active one (the original stays).
    func copySubjectToNewLayer(name: String, actionName: String) async throws {
        commitFloatingIfNeeded()
        cancelLivePreview()
        guard let visible = flattenedImage(), let analysis = analysisImage() else { throw EditError.allocationFailed }
        let before = stamp(), space = colorSpace
        let result = try await Task.detached(priority: .userInitiated) {
            let mask = try SmartImageOps.subjectMask(of: analysis)
            return try SmartImageOps.applying(mask, to: visible, colorSpace: space)
        }.value
        commitFloatingIfNeeded()
        cancelLivePreview()
        guard isUnchanged(since: before) else { throw EditError.canvasChanged }
        guard let buffer = RasterBuffer(image: result, colorSpace: colorSpace) else { throw EditError.allocationFailed }
        let layer = Layer(name: uniqueLayerName(base: name), buffer: buffer)
        performStructuralEdit(actionName: actionName) { m in
            m.insertLayer(layer, at: (m.activeLayerIndex ?? m.layers.count - 1) + 1)
            m.activeLayerID = layer.id
        }
    }

    /// Applies Core Image's automatic enhancement to the active layer.
    func autoEnhanceActiveLayer(actionName: String) async throws {
        commitFloatingIfNeeded()
        cancelLivePreview()
        guard let layer = activeLayer, let source = layer.buffer.copyImage() else { throw EditError.allocationFailed }
        let before = stamp(), layerID = layer.id, space = colorSpace
        let result = try await Task.detached(priority: .userInitiated) {
            try SmartImageOps.autoEnhanced(source, colorSpace: space)
        }.value
        // Core Image suggested no adjustment: nothing changed, so no (empty) undo step.
        if result === source { return }
        try install(result, onLayer: layerID, since: before, actionName: actionName)
    }

    /// Replaces the layer's buffer with `image` as one undo step (a new buffer, so the snapshot
    /// keeps the old pixels by reference; see `Layer`).
    private func install(_ image: CGImage, onLayer id: UUID, since before: Stamp, actionName: String) throws {
        commitFloatingIfNeeded()
        cancelLivePreview()
        guard isUnchanged(since: before), image.width == width, image.height == height else { throw EditError.canvasChanged }
        guard let buffer = RasterBuffer(image: image, colorSpace: colorSpace) else { throw EditError.allocationFailed }
        performStructuralEdit(actionName: actionName) { m in
            guard let layer = m.layer(id: id) else { return }
            layer.buffer = buffer
            layer.contentRevision &+= 1
        }
    }
}
