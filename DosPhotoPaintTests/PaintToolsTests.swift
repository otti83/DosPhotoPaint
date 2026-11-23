import XCTest
import AppKit
@testable import DosPhotoPaint

@MainActor final class PaintToolsTests: AppTestCase {
    /// ToolContext holds its view unowned.
    private let view = CanvasView(frame: .zero)

    // MARK: FloodFill

    /// Builds a straight-opaque bitmap from rows of gray values; 0xFF → alpha 0 when `clear` contains it.
    private func bitmap(_ rows: [[UInt8]], alphaFor: (UInt8) -> UInt8 = { _ in 255 }) -> FloodFill.Bitmap {
        let h = rows.count, w = rows[0].count
        var data = [UInt8]()
        for r in rows { for v in r {
            let a = alphaFor(v)
            let p = UInt8((Int(v) * Int(a) + 127) / 255)
            data += [p, p, p, a]
        } }
        return FloodFill.Bitmap(data: data, width: w, height: h, bytesPerRow: w * 4)
    }

    func testContiguousStopsAtBarrier() {
        let bmp = bitmap([[0, 0, 100, 0],
                          [0, 0, 100, 0],
                          [0, 0, 100, 0]])
        let r = FloodFill.fill(bmp, seedX: 0, seedY: 0, options: .init(tolerance: 0, contiguous: true))!
        XCTAssertEqual(r.bounds, CGRect(x: 0, y: 0, width: 2, height: 3))
        XCTAssertEqual(r.mask.filter { $0 == 255 }.count, 6)
        XCTAssertEqual(r.mask[3], 0)
    }

    func testGlobalFillsDisconnectedRegions() {
        let bmp = bitmap([[0, 100, 0]])
        let r = FloodFill.fill(bmp, seedX: 0, seedY: 0, options: .init(tolerance: 0, contiguous: false))!
        XCTAssertEqual(r.mask, [255, 0, 255])
    }

    func testToleranceIncludesNearColors() {
        let bmp = bitmap([[10, 20, 60]])
        let tight = FloodFill.fill(bmp, seedX: 0, seedY: 0, options: .init(tolerance: 5, contiguous: true))!
        XCTAssertEqual(tight.mask, [255, 0, 0])
        let loose = FloodFill.fill(bmp, seedX: 0, seedY: 0, options: .init(tolerance: 15, contiguous: true))!
        XCTAssertEqual(loose.mask, [255, 255, 0])
    }

    func testAlphaChannelIsCompared() {
        // Same colour, different alpha: opaque white vs transparent.
        let bmp = bitmap([[255, 255, 255, 255]], alphaFor: { _ in 255 })
        var data = bmp.data
        data[7] = 0; data[4] = 0; data[5] = 0; data[6] = 0   // second pixel fully transparent
        let b = FloodFill.Bitmap(data: data, width: 4, height: 1, bytesPerRow: 16)
        let r = FloodFill.fill(b, seedX: 0, seedY: 0, options: .init(tolerance: 10, contiguous: true))!
        XCTAssertEqual(r.mask, [255, 0, 255, 255].enumerated().map { $0.offset == 2 || $0.offset == 3 ? 0 : $0.element })
        // Transparent pixels match each other whatever their hidden colour is.
        var t = FloodFill.Bitmap(data: [0, 0, 0, 0, 0, 0, 0, 0], width: 2, height: 1, bytesPerRow: 8)
        t.data[0] = 0
        XCTAssertEqual(FloodFill.fill(t, seedX: 1, seedY: 0, options: .init(tolerance: 0, contiguous: true))!.mask, [255, 255])
    }

    func testSeedOutsideReturnsNil() {
        let bmp = bitmap([[0]])
        XCTAssertNil(FloodFill.fill(bmp, seedX: 1, seedY: 0, options: .init(tolerance: 0, contiguous: true)))
    }

    func testEdgeBlendAddsPartialCoverage() {
        let bmp = bitmap([[0, 0, 40, 200]])
        let r = FloodFill.fill(bmp, seedX: 0, seedY: 0, options: .init(tolerance: 10, contiguous: true, edgeBlend: true))!
        XCTAssertEqual(r.mask[1], 255)
        XCTAssertGreaterThan(r.mask[2], 0)
        XCTAssertLessThan(r.mask[2], 255)
        XCTAssertEqual(r.mask[3], 0)
    }

    // MARK: Shape geometry

    func testBoxConstrainAndCenter() {
        let a = CGPoint(x: 10, y: 10)
        XCTAssertEqual(ShapeGeometry.box(start: a, end: CGPoint(x: 30, y: 15), square: false, fromCenter: false), CGRect(x: 10, y: 10, width: 20, height: 5))
        XCTAssertEqual(ShapeGeometry.box(start: a, end: CGPoint(x: 30, y: 15), square: true, fromCenter: false), CGRect(x: 10, y: 10, width: 20, height: 20))
        XCTAssertEqual(ShapeGeometry.box(start: a, end: CGPoint(x: 0, y: 5), square: true, fromCenter: false), CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(ShapeGeometry.box(start: a, end: CGPoint(x: 14, y: 12), square: false, fromCenter: true), CGRect(x: 6, y: 8, width: 8, height: 4))
    }

    func testLineConstrainSnapsTo45Degrees() {
        let (_, e) = ShapeGeometry.line(start: .zero, end: CGPoint(x: 100, y: 10), constrain: true, fromCenter: false)
        XCTAssertEqual(e.y, 0, accuracy: 0.001)
        XCTAssertEqual(e.x, hypot(100, 10), accuracy: 0.001)
        let (a, b) = ShapeGeometry.line(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 9, y: 5), constrain: false, fromCenter: true)
        XCTAssertEqual(a, CGPoint(x: 1, y: 5)); XCTAssertEqual(b, CGPoint(x: 9, y: 5))
    }

    func testPolygonPoints() {
        let pts = ShapeGeometry.polygonPoints(in: CGRect(x: 0, y: 0, width: 20, height: 20), sides: 4)
        XCTAssertEqual(pts.count, 4)
        XCTAssertEqual(pts[0].x, 10, accuracy: 0.001); XCTAssertEqual(pts[0].y, 0, accuracy: 0.001)
    }

    // MARK: Undo

    func testStrokeCommitIsOneUndoStep() throws {
        let canvas = try XCTUnwrap(CanvasModel(width: 64, height: 64, background: CGColor(gray: 1, alpha: 1)))
        let um = UndoManager()
        um.groupsByEvent = false
        canvas.undoManager = um
        let ctx = makeContext(canvas)
        ctx.settings.primaryColor = .black
        let tool = StrokeTool(kind: .pen)
        um.beginUndoGrouping()
        func ev(_ x: CGFloat) -> ToolEvent { ToolEvent(location: CGPoint(x: x, y: 20), pressure: 1, modifiers: [], clickCount: 1, isTablet: false) }
        tool.mouseDown(ev(5), context: ctx)
        tool.mouseDragged(ev(20), context: ctx)
        tool.mouseDragged(ev(40), context: ctx)
        tool.mouseUp(ev(40), context: ctx)
        um.endUndoGrouping()
        XCTAssertTrue(um.canUndo)
        let before = canvas.layers[0].buffer.pixel(x: 20, y: 20)!
        XCTAssertLessThan(before.r, 255)
        um.undo()
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 20, y: 20)!.r, 255)
        XCTAssertFalse(um.canUndo)
    }

    private func makeContext(_ canvas: CanvasModel) -> ToolContext {
        let suite = "paintToolsTests.\(UUID().uuidString)"
        let settings = ToolSettings(defaults: UserDefaults(suiteName: suite)!)
        UserDefaults.standard.removePersistentDomain(forName: suite)
        settings.primaryColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        settings.secondaryColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        settings.opacity = 1
        return ToolContext(canvas: canvas, settings: settings, view: view, windowState: WindowState())
    }

    func testFillToolOneUndoStep() throws {
        let canvas = try XCTUnwrap(CanvasModel(width: 32, height: 32, background: CGColor(gray: 1, alpha: 1)))
        let um = UndoManager(); um.groupsByEvent = false; canvas.undoManager = um
        let ctx = makeContext(canvas)
        um.beginUndoGrouping()
        FillTool().mouseDown(ToolEvent(location: CGPoint(x: 3, y: 3), pressure: 1, modifiers: [], clickCount: 1, isTablet: false), context: ctx)
        um.endUndoGrouping()
        let p = canvas.layers[0].buffer.pixel(x: 10, y: 10)!
        XCTAssertEqual(p.r, 255); XCTAssertEqual(p.g, 0); XCTAssertEqual(p.b, 0)
        um.undo()
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 10, y: 10)!.g, 255)
    }

    func testShapeToolCommitsAndUndoes() throws {
        let canvas = try XCTUnwrap(CanvasModel(width: 64, height: 64, background: CGColor(gray: 1, alpha: 1)))
        let um = UndoManager(); um.groupsByEvent = false; canvas.undoManager = um
        let ctx = makeContext(canvas)
        ctx.settings.shapeKind = .rectangle
        ctx.settings.shapeFillEnabled = true
        let tool = ShapeTool()
        func ev(_ x: CGFloat, _ y: CGFloat) -> ToolEvent { ToolEvent(location: CGPoint(x: x, y: y), pressure: 1, modifiers: [], clickCount: 1, isTablet: false) }
        um.beginUndoGrouping()
        tool.mouseDown(ev(10, 10), context: ctx)
        tool.mouseDragged(ev(30, 30), context: ctx)
        tool.mouseUp(ev(30, 30), context: ctx)
        um.endUndoGrouping()
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 20, y: 20)!.b, 255)   // secondary fill
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 20, y: 20)!.r, 0)
        um.undo()
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 20, y: 20)!.r, 255)
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 20, y: 20)!.g, 255)
    }
}

@MainActor final class EngineReviewPaintTests: AppTestCase {
    private let view = CanvasView(frame: .zero)

    func testFillCoverageToPixelsMatchesColourAndPartialCoverage() throws {
        // Opaque fill at 50 % opacity over white: halfway between white and red.
        let canvas = try XCTUnwrap(CanvasModel(width: 16, height: 16, background: CGColor(gray: 1, alpha: 1)))
        let settings = ToolSettings(defaults: UserDefaults(suiteName: "EngineReviewPaint.\(UUID().uuidString)")!)
        settings.primaryColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        settings.opacity = 0.5
        let ctx = ToolContext(canvas: canvas, settings: settings, view: view, windowState: WindowState())
        FillTool().mouseDown(ToolEvent(location: CGPoint(x: 2, y: 2), pressure: 1, modifiers: [], clickCount: 1, isTablet: false), context: ctx)
        let p = try XCTUnwrap(canvas.layers[0].buffer.pixel(x: 8, y: 8))
        XCTAssertEqual(Int(p.r), 255)
        XCTAssertEqual(Int(p.g), 128, accuracy: 2)
        XCTAssertEqual(Int(p.b), 128, accuracy: 2)
    }

    func testEraserOnLayerWithSelectionOnlyErasesInside() throws {
        let canvas = try XCTUnwrap(CanvasModel(width: 40, height: 40, background: CGColor(gray: 1, alpha: 1)))
        let um = UndoManager(); um.groupsByEvent = false; canvas.undoManager = um
        canvas.setSelection(.rect(CGRect(x: 0, y: 0, width: 20, height: 40)), undoable: false)
        let settings = ToolSettings(defaults: UserDefaults(suiteName: "EngineReviewPaint.\(UUID().uuidString)")!)
        settings.eraserSize = 40
        let ctx = ToolContext(canvas: canvas, settings: settings, view: view, windowState: WindowState())
        let tool = StrokeTool(kind: .eraser)
        func ev(_ x: CGFloat) -> ToolEvent { ToolEvent(location: CGPoint(x: x, y: 20), pressure: 1, modifiers: [], clickCount: 1, isTablet: false) }
        um.beginUndoGrouping()
        tool.mouseDown(ev(10), context: ctx)
        tool.mouseDragged(ev(30), context: ctx)
        tool.mouseUp(ev(30), context: ctx)
        um.endUndoGrouping()
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 10, y: 20)?.a, 0)
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 30, y: 20)?.a, 255)
        um.undo()
        XCTAssertEqual(canvas.layers[0].buffer.pixel(x: 10, y: 20)?.a, 255)
    }
}
