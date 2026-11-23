import XCTest
@testable import DosPhotoPaint

@MainActor
final class SelectionTests: AppTestCase {
    private func makeModel() -> (CanvasModel, UndoManager) {
        let m = CanvasModel(width: 100, height: 80, background: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))!
        let um = UndoManager()
        um.groupsByEvent = false
        m.undoManager = um
        m.layers[0].buffer.fill(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), in: CGRect(x: 10, y: 10, width: 20, height: 20))
        return (m, um)
    }

    private func pixels(_ m: CanvasModel) -> Data {
        m.layers[0].buffer.withMutablePixels { p, bpr in Data(bytes: p, count: bpr * m.height) }!
    }

    private func group(_ um: UndoManager, _ body: () -> Void) {
        um.beginUndoGrouping(); body(); um.endUndoGrouping()
    }

    private func isRed(_ m: CanvasModel, _ x: Int, _ y: Int) -> Bool {
        let p = m.layers[0].buffer.pixel(x: x, y: y)!
        return p.r == 255 && p.g == 0 && p.b == 0 && p.a == 255
    }

    func testLiftMoveCommitIsOneUndoStepWithExactRestore() {
        let (m, um) = makeModel()
        let original = pixels(m)
        group(um) { m.setSelection(.rect(CGRect(x: 10, y: 10, width: 20, height: 20)), actionName: "Select") }
        group(um) { XCTAssertTrue(m.liftSelection(transparentColor: nil)) }
        XCTAssertNotNil(m.floating)
        XCTAssertEqual(m.layers[0].buffer.pixel(x: 15, y: 15)?.a, 0)   // source cleared
        m.setFloatingTransform(CGAffineTransform(translationX: 40, y: 20))
        XCTAssertEqual(m.selection?.bounds, CGRect(x: 40, y: 20, width: 20, height: 20))
        m.commitFloating()   // registers nothing itself
        XCTAssertNil(m.floating)
        XCTAssertTrue(isRed(m, 45, 25))
        XCTAssertEqual(m.layers[0].buffer.pixel(x: 15, y: 15)?.a, 0)
        let moved = pixels(m)

        um.undo()
        XCTAssertEqual(pixels(m), original)
        XCTAssertEqual(m.selection?.bounds, CGRect(x: 10, y: 10, width: 20, height: 20))
        um.redo()
        XCTAssertEqual(pixels(m), moved)
        um.undo()
        XCTAssertEqual(pixels(m), original)
        var steps = 0
        while um.canUndo && steps < 5 { um.undo(); steps += 1 }
        XCTAssertEqual(steps, 1, "only the selection step should remain")
        XCTAssertNil(m.selection)
    }

    func testCancelRestoresExactlyAndLeavesNoUndoResidue() {
        let (m, um) = makeModel()
        let original = pixels(m)
        group(um) { m.setSelection(.rect(CGRect(x: 10, y: 10, width: 20, height: 20)), actionName: "Select") }
        group(um) { m.liftSelection(transparentColor: nil) }
        m.setFloatingTransform(CGAffineTransform(translationX: 5, y: 5))
        m.cancelFloating()
        XCTAssertNil(m.floating)
        XCTAssertEqual(pixels(m), original)
        XCTAssertEqual(m.selection?.bounds, CGRect(x: 10, y: 10, width: 20, height: 20))
        um.undo()   // only the selection step remains
        XCTAssertNil(m.selection)
        XCTAssertFalse(um.canUndo)
    }

    func testUndoWhileFloatingCancels() {
        let (m, um) = makeModel()
        let original = pixels(m)
        group(um) { m.setSelection(.rect(CGRect(x: 10, y: 10, width: 20, height: 20)), actionName: "Select") }
        group(um) { m.liftSelection(transparentColor: nil) }
        um.undo()
        XCTAssertNil(m.floating)
        XCTAssertEqual(pixels(m), original)
    }

    func testCropAllLayersAndUndo() {
        let (m, um) = makeModel()
        group(um) { XCTAssertTrue(m.crop(to: CGRect(x: 10, y: 10, width: 30, height: 25))) }
        XCTAssertEqual(m.width, 30)
        XCTAssertEqual(m.height, 25)
        XCTAssertTrue(m.layers.allSatisfy { $0.buffer.width == 30 && $0.buffer.height == 25 })
        XCTAssertTrue(isRed(m, 0, 0))
        um.undo()
        XCTAssertEqual(m.width, 100)
        XCTAssertEqual(m.height, 80)
        XCTAssertTrue(m.layers.allSatisfy { $0.buffer.width == 100 && $0.buffer.height == 80 })
        XCTAssertTrue(isRed(m, 15, 15))
    }

    func testDeleteAndCutUndo() {
        let (m, um) = makeModel()
        let original = pixels(m)
        group(um) { m.setSelection(.rect(CGRect(x: 5, y: 5, width: 30, height: 30)), actionName: "Select") }
        group(um) { XCTAssertTrue(m.deleteSelectionContents(actionName: "Cut")) }
        XCTAssertEqual(m.layers[0].buffer.pixel(x: 15, y: 15)?.a, 0)
        XCTAssertEqual(m.layers[0].buffer.pixel(x: 50, y: 50)?.a, 255)
        um.undo()
        XCTAssertEqual(pixels(m), original)
    }

    func testTransparentSelectionAndPasteCommit() {
        let (m, um) = makeModel()
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        group(um) { m.setSelection(.rect(CGRect(x: 5, y: 5, width: 30, height: 30)), actionName: "Select") }
        group(um) { m.liftSelection(transparentColor: white) }
        // The white pixels of the lifted image are transparent, the red ones are kept.
        let img = m.floating!.image
        XCTAssertEqual(img.width, 30)
        let rep = NSBitmapImageRep(cgImage: img)
        XCTAssertEqual(rep.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertEqual(rep.colorAt(x: 10, y: 10)?.alphaComponent, 1)
        m.cancelFloating()
    }
}

/// Review findings: live-preview clipping, no-op undo steps, hidden layers, size limits.
@MainActor
final class EngineReviewSelectionTests: AppTestCase {
    private func make() -> (CanvasModel, UndoManager) {
        let m = CanvasModel(width: 100, height: 80, background: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))!
        let um = UndoManager()
        um.groupsByEvent = false
        m.undoManager = um
        return (m, um)
    }

    private func paintPreview(_ m: CanvasModel, rect: CGRect) {
        let layer = m.activeLayer!
        let buffer = m.beginLivePreview(layerID: layer.id, opacity: 1)!
        buffer.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        buffer.context.fill(rect)
        m.livePreviewDidChange(rect)
    }

    func testLivePreviewIsClippedToSelectionLikeTheCommit() {
        let (m, _) = make()
        m.setSelection(.rect(CGRect(x: 0, y: 0, width: 50, height: 80)), undoable: false)
        paintPreview(m, rect: CGRect(x: 40, y: 10, width: 30, height: 10))
        m.updateComposite()
        XCTAssertEqual(m.composite.pixel(x: 45, y: 15)?.r, 0, "inside the selection the stroke is shown")
        XCTAssertEqual(m.composite.pixel(x: 60, y: 15)?.r, 255, "outside the selection nothing is shown")
        m.commitLivePreview(actionName: "Pen")
        XCTAssertEqual(m.layers[0].buffer.pixel(x: 45, y: 15)?.r, 0)
        XCTAssertEqual(m.layers[0].buffer.pixel(x: 60, y: 15)?.r, 255)
    }

    func testStrokeEntirelyOutsideSelectionRegistersNoUndoStep() {
        let (m, um) = make()
        m.setSelection(.rect(CGRect(x: 0, y: 0, width: 20, height: 20)), undoable: false)
        paintPreview(m, rect: CGRect(x: 60, y: 40, width: 10, height: 10))
        m.commitLivePreview(actionName: "Pen")
        XCTAssertFalse(um.canUndo)
        XCTAssertNil(m.livePreview)
        m.updateComposite()
        XCTAssertEqual(m.composite.pixel(x: 65, y: 45)?.r, 255)
    }

    func testCannotLiftFromHiddenLayer() {
        let (m, _) = make()
        m.setSelection(.rect(CGRect(x: 10, y: 10, width: 20, height: 20)), undoable: false)
        m.layers[0].isVisible = false
        XCTAssertFalse(m.liftSelection(transparentColor: nil))
        XCTAssertNil(m.floating)
        XCTAssertEqual(m.layers[0].buffer.pixel(x: 15, y: 15)?.a, 255, "pixels untouched")
    }

    func testExpandCanvasRejectsUnsupportedSizes() {
        let (m, um) = make()
        XCTAssertFalse(m.expandCanvas(toWidth: 40_000, height: 80, background: nil))
        XCTAssertFalse(m.expandCanvas(toWidth: 16_000, height: 16_000, background: nil))
        XCTAssertEqual(m.width, 100)
        XCTAssertFalse(um.canUndo)
    }

    func testSelectionToolReleasesCanvasOnDeactivate() throws {
        weak var weakCanvas: CanvasModel?
        let tool = SelectionTool(kind: .rectangleSelect)
        let view = CanvasView(frame: .zero)
        autoreleasepool {
            let m = CanvasModel(width: 10, height: 10, background: nil)!
            weakCanvas = m
            let settings = ToolSettings(defaults: UserDefaults(suiteName: "EngineReview.\(UUID().uuidString)")!)
            let ctx = ToolContext(canvas: m, settings: settings, view: view, windowState: WindowState())
            tool.activate(context: ctx)
            tool.deactivate(context: ctx)
        }
        XCTAssertNil(weakCanvas, "a deactivated tool must not keep the document's canvas alive")
    }
}
