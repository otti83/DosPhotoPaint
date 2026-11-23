import AppKit

/// A pointer event already converted to image pixel coordinates (y-down, unrounded).
struct ToolEvent {
    var location: CGPoint
    /// 0…1. 1 for mice; tablet pressure for pens.
    var pressure: CGFloat
    var modifiers: NSEvent.ModifierFlags
    var clickCount: Int
    var isTablet: Bool

    var shift: Bool { modifiers.contains(.shift) }
    var option: Bool { modifiers.contains(.option) }
    var command: Bool { modifiers.contains(.command) }
}

/// Everything a tool may touch while handling events.
final class ToolContext {
    let canvas: CanvasModel
    let settings: ToolSettings
    unowned let view: CanvasView
    let windowState: WindowState

    init(canvas: CanvasModel, settings: ToolSettings, view: CanvasView, windowState: WindowState) {
        self.canvas = canvas
        self.settings = settings
        self.view = view
        self.windowState = windowState
    }

    /// Current zoom (1 = 100 %). Use to keep overlay line widths constant on screen.
    var magnification: CGFloat { view.magnification }
    var undoManager: UndoManager? { canvas.undoManager }

    /// Requests a redraw of overlay graphics covering `rect` (pixel coordinates).
    func setNeedsOverlayDisplay(_ rect: CGRect? = nil) { view.setNeedsOverlayDisplay(rect) }
}

/// A Paint tool. Tools are long-lived per window; they receive pixel-space events from `CanvasView`.
///
/// Contract:
/// - One mouseDown…mouseUp gesture = at most one undo step.
/// - Painting goes through `CanvasModel.beginLivePreview` / `commitLivePreview`
///   or `applyRegionEdit`; never write layer pixels without registering undo.
/// - `deactivate` must commit or cancel anything pending (text box, floating selection).
protocol CanvasTool: AnyObject {
    var kind: ToolKind { get }
    func activate(context: ToolContext)
    func deactivate(context: ToolContext)
    func mouseDown(_ event: ToolEvent, context: ToolContext)
    func mouseDragged(_ event: ToolEvent, context: ToolContext)
    func mouseUp(_ event: ToolEvent, context: ToolContext)
    func mouseMoved(_ event: ToolEvent, context: ToolContext)
    /// Modifier keys changed during a gesture (e.g. Shift constraint should update live).
    func flagsChanged(_ event: ToolEvent, context: ToolContext)
    /// Return true if handled (Return/Escape/Delete/arrow keys…).
    func keyDown(_ event: NSEvent, context: ToolContext) -> Bool
    func cursor(context: ToolContext) -> NSCursor
    /// Draws overlay graphics (selection outline, handles, brush outline…) into the view's
    /// context; user space = image pixels (y-down). Divide hairline widths by `context.magnification`.
    func drawOverlay(in ctx: CGContext, context: ToolContext)
    /// Abort the current gesture without committing.
    func cancel(context: ToolContext)
}

extension CanvasTool {
    func activate(context: ToolContext) {}
    func deactivate(context: ToolContext) {}
    func mouseDragged(_ event: ToolEvent, context: ToolContext) {}
    func mouseUp(_ event: ToolEvent, context: ToolContext) {}
    func mouseMoved(_ event: ToolEvent, context: ToolContext) {}
    func flagsChanged(_ event: ToolEvent, context: ToolContext) {}
    func keyDown(_ event: NSEvent, context: ToolContext) -> Bool { false }
    func cursor(context: ToolContext) -> NSCursor { .crosshair }
    func drawOverlay(in ctx: CGContext, context: ToolContext) {}
    func cancel(context: ToolContext) {}
}
