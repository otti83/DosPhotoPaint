import CoreGraphics
import Foundation

/// The current selection area in pixel coordinates (y-down).
struct CanvasSelection {
    /// Closed path in pixel coordinates.
    var path: CGPath
    var bounds: CGRect { path.boundingBoxOfPath }

    static func rect(_ r: CGRect) -> CanvasSelection { CanvasSelection(path: CGPath(rect: r.standardized, transform: nil)) }
}

/// Pixels lifted from a layer (or pasted) that float above `layerID` until committed.
/// Rendered by `CanvasRenderer` on top of its layer, transformed by `transform`
/// (which maps the image's own pixel space — origin top-left, size image.width × image.height —
/// into canvas pixel space).
struct FloatingContent {
    var layerID: UUID
    var image: CGImage
    var transform: CGAffineTransform
    var opacity: Double = 1
    /// Bookkeeping for floating content created by the selection module (lift / paste).
    /// nil for floating content owned by other tools (merged by the plain `commitFloating` path).
    var session: FloatSession?

    /// Bounding box of the transformed image in canvas pixels.
    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: image.width, height: image.height).applying(transform)
    }
}

/// Scratch buffer a tool paints into during a gesture; composited live above `layerID`
/// and merged into the layer on commit.
struct LivePreview {
    var layerID: UUID
    var buffer: RasterBuffer
    var opacity: Double
    /// `.normal` for painting, `.destinationOut` for erasing alpha.
    var blendMode: CGBlendMode
    /// Pixel rect touched so far.
    var dirtyRect: CGRect
}

/// Bookkeeping of one lift/paste: what is needed to commit it as a single undo step and to
/// cancel it exactly. Doubles as the undo-manager target of the temporary "cancel" action that
/// is registered when content starts floating and is the ONE undo step of the whole
/// lift + move + commit: undone mid-float it cancels the float, after the commit it restores
/// the pre-lift pixels (see `CanvasModel.undoFloat`).
final class FloatSession {
    weak var model: CanvasModel?
    /// Selection before the lift/paste (restored on undo/cancel).
    let originalSelection: CanvasSelection?
    /// Selection outline in the floating image's own pixel space (follows the transform).
    let localPath: CGPath
    /// Lift only: the source rect and its exact pixels before the source was cleared.
    let liftRect: CGRect?
    let before: CGImage?
    /// Set when the float was merged: what ⌘Z needs to undo it (the pre-lift pixels of `rect`).
    var committed: Committed?

    struct Committed {
        let layerID: UUID
        let rect: CGRect
        let previous: CGImage
    }

    init(model: CanvasModel, originalSelection: CanvasSelection?, localPath: CGPath, liftRect: CGRect?, before: CGImage?) {
        self.model = model
        self.originalSelection = originalSelection
        self.localPath = localPath
        self.liftRect = liftRect
        self.before = before
    }
}
