import AppKit

extension CanvasView {
    /// True when the image is larger than the visible area, i.e. dragging pans it.
    var canPan: Bool {
        guard let sv = scrollView else { return false }
        let docSize = frame.size.applying(CGAffineTransform(scaleX: magnification, y: magnification))
        return docSize.width > sv.contentSize.width + 0.5 || docSize.height > sv.contentSize.height + 0.5
    }
}

extension CanvasView: NSDraggingSource {
    /// Dragging the image to other apps copies it; dropping back onto this window is refused
    /// by `DropHandling` anyway.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
