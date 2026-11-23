import Foundation

/// Creates tool instances (one per kind per window).
enum ToolFactory {
    static func make(_ kind: ToolKind) -> CanvasTool? {
        switch kind {
        case .pen, .brush, .eraser: StrokeTool(kind: kind)
        case .fill: FillTool()
        case .eyedropper: EyedropperTool()
        case .shape: ShapeTool()
        case .hand: HandTool()
        case .text: TextTool()
        case .rectangleSelect, .lassoSelect: SelectionTool(kind: kind)
        case .crop: CropTool()
        }
    }
}

/// Panning is performed by `CanvasView` itself; the tool only exists for the cursor/selection.
final class HandTool: CanvasTool {
    let kind = ToolKind.hand
    func mouseDown(_ event: ToolEvent, context: ToolContext) {}
}
