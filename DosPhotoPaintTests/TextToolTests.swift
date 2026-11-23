import XCTest
import AppKit
@testable import DosPhotoPaint

@MainActor
final class TextToolTests: AppTestCase {
    /// ToolContext holds its view unowned, so keep it alive for the test's duration.
    private var view: CanvasView?

    private func makeContext() -> (ToolContext, CanvasModel, UndoManager)? {
        guard let model = CanvasModel(width: 300, height: 200, background: CGColor(red: 1, green: 1, blue: 1, alpha: 1)) else { return nil }
        let um = UndoManager()
        um.groupsByEvent = false
        model.undoManager = um
        let view = CanvasView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        view.content = .canvas(model)
        self.view = view
        let settings = ToolSettings(defaults: UserDefaults(suiteName: "TextToolTests")!)
        settings.fontName = "Helvetica"
        settings.fontSize = 32
        settings.primaryColor = .black
        return (ToolContext(canvas: model, settings: settings, view: view, windowState: WindowState()), model, um)
    }

    /// Programmatic typing (no window/key events in unit tests), using the view's typing attributes.
    private func type(_ text: String, into tv: EditorTextView) {
        tv.textStorage?.append(NSAttributedString(string: text, attributes: tv.typingAttributes))
    }

    private func darkPixels(_ model: CanvasModel, in rect: CGRect) -> Int {
        var n = 0
        let buf = model.layers[0].buffer
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                if let p = buf.pixel(x: x, y: y), p.r < 128 { n += 1 }
            }
        }
        return n
    }

    func testRenderingProducesPixelsInsideBoxOnly() throws {
        let (ctx, model, _) = try XCTUnwrap(makeContext())
        let tool = TextTool()
        tool.activate(context: ctx)
        let box = CGRect(x: 20, y: 30, width: 200, height: 60)
        tool.beginEditing(in: box, context: ctx)
        let tv = try XCTUnwrap(tool.textView)
        type("Hello", into: tv)
        XCTAssertTrue(tool.commit(force: false))
        XCTAssertGreaterThan(darkPixels(model, in: box), 50)
        XCTAssertEqual(darkPixels(model, in: CGRect(x: 0, y: 100, width: 300, height: 100)), 0)
        XCTAssertEqual(darkPixels(model, in: CGRect(x: 0, y: 0, width: 20, height: 100)), 0)
        XCTAssertNil(tool.textView)
    }

    func testCommitIsOneUndoStep() throws {
        let (ctx, model, um) = try XCTUnwrap(makeContext())
        let tool = TextTool()
        tool.activate(context: ctx)
        let box = CGRect(x: 20, y: 30, width: 200, height: 60)
        tool.beginEditing(in: box, context: ctx)
        type("Line1\nLine2", into: try XCTUnwrap(tool.textView))
        um.beginUndoGrouping()
        tool.commit(force: true)
        um.endUndoGrouping()
        XCTAssertGreaterThan(darkPixels(model, in: box), 0)
        XCTAssertEqual(um.undoActionName, "Text")
        um.undo()
        XCTAssertEqual(darkPixels(model, in: box), 0)
        XCTAssertFalse(um.canUndo)
    }

    func testEmptyTextCommitsNothing() throws {
        let (ctx, model, um) = try XCTUnwrap(makeContext())
        let tool = TextTool()
        tool.activate(context: ctx)
        tool.beginEditing(in: CGRect(x: 10, y: 10, width: 100, height: 40), context: ctx)
        tool.commit(force: true)
        XCTAssertFalse(um.canUndo)
        XCTAssertEqual(darkPixels(model, in: model.bounds), 0)
    }
}

@MainActor
final class TextAttributeTests: AppTestCase {
    func testUnderlineAttributeAlwaysPresentSoItCanBeCleared() {
        let s = ToolSettings(defaults: UserDefaults(suiteName: "TextAttributeTests")!)
        s.underline = false
        XCTAssertEqual(TextTool.attributes(for: s)[.underlineStyle] as? Int, 0)
        s.underline = true
        XCTAssertEqual(TextTool.attributes(for: s)[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
    }
}

@MainActor
final class EngineReviewTextTests: AppTestCase {
    func testDeactivateWithUncommittableBoxDoesNotLeaveEditorBehind() throws {
        let model = try XCTUnwrap(CanvasModel(width: 200, height: 100, background: CGColor(red: 1, green: 1, blue: 1, alpha: 1)))
        let um = UndoManager(); um.groupsByEvent = false; model.undoManager = um
        let view = CanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        view.content = .canvas(model)
        let settings = ToolSettings(defaults: UserDefaults(suiteName: "EngineReviewText")!)
        let ctx = ToolContext(canvas: model, settings: settings, view: view, windowState: WindowState())
        let tool = TextTool()
        tool.activate(context: ctx)
        tool.beginEditing(in: CGRect(x: 5, y: 5, width: 120, height: 40), context: ctx)
        let tv = try XCTUnwrap(tool.textView)
        tv.textStorage?.append(NSAttributedString(string: "Hi", attributes: tv.typingAttributes))
        model.layers[0].isVisible = false   // commit is impossible now
        tool.deactivate(context: ctx)
        XCTAssertNil(tool.textView)
        XCTAssertNil(tool.box)
        XCTAssertNil(tv.superview, "the editor must be removed from the canvas")
        XCTAssertFalse(um.canUndo)
    }
}
