import AppKit
import XCTest
@testable import DosPhotoPaint

@MainActor
final class NewCanvasAndZoomTests: AppTestCase {
    // MARK: Zoom slider mapping

    func testSliderMappingEndpointsAndRoundTrip() {
        XCTAssertEqual(ZoomLevels.sliderPosition(forZoom: ZoomLevels.minimum), 0, accuracy: 1e-9)
        XCTAssertEqual(ZoomLevels.sliderPosition(forZoom: ZoomLevels.maximum), 1, accuracy: 1e-9)
        XCTAssertEqual(ZoomLevels.zoom(forSliderPosition: 0), ZoomLevels.minimum, accuracy: 1e-6)
        XCTAssertEqual(ZoomLevels.zoom(forSliderPosition: 1), ZoomLevels.maximum, accuracy: 1e-4)
        for z: CGFloat in [0.1, 0.25, 0.5, 1, 2, 7.5, 16, 32] {
            let back = ZoomLevels.zoom(forSliderPosition: ZoomLevels.sliderPosition(forZoom: z))
            XCTAssertEqual(back, z, accuracy: z * 1e-6)
        }
        // Logarithmic: 100 % sits at log(10)/log(320) of the track.
        XCTAssertEqual(ZoomLevels.sliderPosition(forZoom: 1), log(10.0) / log(320.0), accuracy: 1e-9)
    }

    func testSliderMappingClamps() {
        XCTAssertEqual(ZoomLevels.zoom(forSliderPosition: -3), ZoomLevels.minimum)
        XCTAssertEqual(ZoomLevels.zoom(forSliderPosition: 9), ZoomLevels.maximum)
        XCTAssertEqual(ZoomLevels.sliderPosition(forZoom: 0.001), 0, accuracy: 1e-9)
        XCTAssertEqual(ZoomLevels.sliderPosition(forZoom: 500), 1, accuracy: 1e-9)
    }

    func testPercentTextParsing() {
        XCTAssertEqual(ZoomLevels.zoom(fromPercentText: "250"), 2.5)
        XCTAssertEqual(ZoomLevels.zoom(fromPercentText: " 50 % "), 0.5)
        XCTAssertEqual(ZoomLevels.zoom(fromPercentText: "99999"), ZoomLevels.maximum)
        XCTAssertEqual(ZoomLevels.zoom(fromPercentText: "1"), ZoomLevels.minimum)
        XCTAssertNil(ZoomLevels.zoom(fromPercentText: "abc"))
        XCTAssertNil(ZoomLevels.zoom(fromPercentText: ""))
    }

    // MARK: New canvas spec

    func testSpecClamping() {
        let range = AppSettings.canvasDimensionRange
        let c = NewCanvasSpec(width: 0, height: 99_999, background: .white).clamped()
        XCTAssertEqual(c.width, range.lowerBound)
        XCTAssertEqual(c.height, range.upperBound)
        XCTAssertTrue(c.isValid)
        let big = NewCanvasSpec(width: 16_384, height: 16_384, background: .white)
        XCTAssertFalse(big.isValid)
        let fixed = big.clamped()
        XCTAssertTrue(fixed.isValid)
        XCTAssertLessThanOrEqual(fixed.width * fixed.height, ImageLoader.maxEditablePixels)
        let ok = NewCanvasSpec(width: 800, height: 600, background: .white)
        XCTAssertEqual(ok.clamped(), ok)
    }

    func testSpecDefaultsFollowSettings() {
        let s = AppSettings.shared
        let spec = NewCanvasSpec.settingsDefault()
        XCTAssertEqual(spec.width, s.paintDefaultWidth)
        XCTAssertEqual(spec.height, s.paintDefaultHeight)
    }

    private func pixel(_ doc: ImageDocument, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        doc.canvas?.layers[0].buffer.pixel(x: x, y: y)
    }

    func testCreateTransparentAndWhiteAndCustom() throws {
        let t = try ImageDocument(type: "public.png", canvas: NewCanvasSpec(width: 40, height: 30, background: .transparent))
        XCTAssertEqual(t.canvas?.width, 40)
        XCTAssertEqual(t.canvas?.height, 30)
        XCTAssertEqual(pixel(t, 5, 5)?.a, 0)

        let w = try ImageDocument(type: "public.png", canvas: NewCanvasSpec(width: 10, height: 10, background: .white))
        let wp = try XCTUnwrap(pixel(w, 3, 3))
        XCTAssertEqual([wp.r, wp.g, wp.b, wp.a], [255, 255, 255, 255])

        let c = try ImageDocument(type: "public.png", canvas: NewCanvasSpec(width: 10, height: 10, background: .custom(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))))
        let cp = try XCTUnwrap(pixel(c, 1, 1))
        XCTAssertEqual([cp.r, cp.g, cp.b, cp.a], [255, 0, 0, 255])

        let s = try ImageDocument(type: "public.png", canvas: NewCanvasSpec(width: 10, height: 10, background: .secondary),
                                  secondary: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        let sp = try XCTUnwrap(pixel(s, 1, 1))
        XCTAssertEqual([sp.r, sp.g, sp.b, sp.a], [0, 0, 255, 255])
    }

    func testOversizedSpecIsClampedOnCreate() throws {
        let d = try ImageDocument(type: "public.png", canvas: NewCanvasSpec(width: 100_000, height: 1, background: .white))
        XCTAssertEqual(d.canvas?.width, AppSettings.canvasDimensionRange.upperBound)
    }

    // MARK: Dialog seam

    func testNewDocumentShowsDialogAndCreatesChosenCanvas() throws {
        let controller = DocumentController.shared
        let saved = controller.newCanvasPresenter
        defer { controller.newCanvasPresenter = saved }
        var calls = 0
        controller.newCanvasPresenter = { _, completion in
            calls += 1
            completion(NewCanvasSpec(width: 64, height: 48, background: .transparent))
        }
        let before = controller.documents.count
        controller.newDocument(nil)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(controller.documents.count, before + 1)
        let doc = try XCTUnwrap(controller.documents.last as? ImageDocument)
        XCTAssertEqual(doc.canvas?.width, 64)
        XCTAssertEqual(pixel(doc, 0, 0)?.a, 0)
    }

    func testCancelledDialogCreatesNothing() {
        let controller = DocumentController.shared
        let saved = controller.newCanvasPresenter
        defer { controller.newCanvasPresenter = saved }
        controller.newCanvasPresenter = { _, completion in completion(nil) }
        let before = controller.documents.count
        controller.newDocument(nil)
        XCTAssertEqual(controller.documents.count, before)
    }

    func testUntitledLaunchPathDoesNotShowDialog() throws {
        let controller = DocumentController.shared
        let saved = controller.newCanvasPresenter
        defer { controller.newCanvasPresenter = saved }
        var calls = 0
        controller.newCanvasPresenter = { _, completion in calls += 1; completion(nil) }
        // What applicationOpenUntitledFile (launch / Dock reopen) does.
        let doc = try controller.openUntitledDocumentAndDisplay(true)
        XCTAssertEqual(calls, 0)
        let image = try XCTUnwrap(doc as? ImageDocument)
        XCTAssertEqual(image.canvas?.width, AppSettings.shared.paintDefaultWidth)
        // The delegate path too.
        XCTAssertTrue(try XCTUnwrap(NSApp.delegate as? AppDelegate ?? AppDelegate()).applicationOpenUntitledFile(NSApp))
        XCTAssertEqual(calls, 0)
    }
}
