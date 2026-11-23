import AppKit

extension MainWindowController {
    /// Places `image` as floating content on the active layer, centred at `point` (pixels) or in
    /// the visible area (kept inside the canvas where it fits). The selection tool becomes active
    /// so it can be moved, resized or rotated before committing. With "transparent selection"
    /// on, pixels equal to the secondary colour become transparent.
    @discardableResult
    func insertImageAsFloating(_ image: CGImage, centeredAt point: CGPoint? = nil) -> Bool {
        guard state.mode == .paint, let canvas, let layer = canvas.activeLayer else { return false }
        canvas.commitFloatingIfNeeded()
        let visible = canvasView.visibleRect.intersection(canvasView.bounds)
        let center = point ?? CGPoint(x: visible.midX, y: visible.midY)
        let w = CGFloat(image.width), h = CGFloat(image.height)
        var origin = CGPoint(x: (center.x - w / 2).rounded(), y: (center.y - h / 2).rounded())
        origin.x = max(0, min(origin.x, CGFloat(canvas.width) - w))
        origin.y = max(0, min(origin.y, CGFloat(canvas.height) - h))
        canvas.beginFloatingPaste(image, origin: origin, layerID: layer.id,
                                  transparentColor: toolSettings.transparentSelection ? toolSettings.secondaryColor : nil)
        activateTool(.rectangleSelect)
        return true
    }
}
