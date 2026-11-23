import XCTest
import CoreGraphics
import ImageIO
@testable import DosPhotoPaint

/// Smart Edit (Vision subject mask, Core Image auto enhance) and the 0.1.0 UI settings.
@MainActor
final class SmartEditTests: AppTestCase {
    private var retainedUndoManagers: [UndoManager] = []
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private func solidImage(_ w: Int, _ h: Int, _ rgba: [UInt8]) -> CGImage {
        let b = RasterBuffer(width: w, height: h, colorSpace: srgb)!
        b.withMutablePixels { p, bpr in
            for y in 0..<h { for x in 0..<w { for c in 0..<4 { p[y * bpr + x * 4 + c] = rgba[c] } } }
        }
        return b.copyImage()!
    }

    private func px(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let b = RasterBuffer(image: image, colorSpace: srgb)!
        let p = b.pixel(x: x, y: y)!
        return [p.r, p.g, p.b, p.a]
    }

    private func canvas(_ image: CGImage) -> CanvasModel {
        let c = CanvasModel(image: image)!
        let manager = UndoManager()
        manager.groupsByEvent = false
        retainedUndoManagers.append(manager)
        c.undoManager = manager
        return c
    }

    /// A real photo with an obvious subject (ships with macOS). Skips when unavailable.
    private func samplePhoto() throws -> CGImage {
        let url = URL(fileURLWithPath: "/Library/User Pictures/Animals/Parrot.heic")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw XCTSkip("sample photo not readable") }
        return image
    }

    // MARK: Mask application (pure)

    func testApplyingMaskScalesPremultipliedPixels() throws {
        let image = solidImage(4, 2, [200, 100, 50, 255])
        // Row 0: full, half, zero, full. Row 1: zero everywhere.
        let mask = SmartImageOps.Mask(width: 4, height: 2, values: [1, 0.5, 0, 1, 0, 0, 0, 0])
        let out = try SmartImageOps.applying(mask, to: image, colorSpace: srgb)
        XCTAssertEqual(px(out, 0, 0), [200, 100, 50, 255])
        XCTAssertEqual(px(out, 1, 0)[3], 128, "half coverage")
        XCTAssertEqual(px(out, 2, 0)[3], 0)
        XCTAssertEqual(px(out, 3, 0), [200, 100, 50, 255])
        XCTAssertEqual(px(out, 0, 1)[3], 0, "mask rows are top-first like the bitmap")
    }

    func testApplyingMaskRejectsSizeMismatch() {
        let image = solidImage(4, 4, [0, 0, 0, 255])
        let mask = SmartImageOps.Mask(width: 2, height: 2, values: [1, 1, 1, 1])
        XCTAssertThrowsError(try SmartImageOps.applying(mask, to: image, colorSpace: srgb))
    }

    // MARK: Auto enhance

    func testAutoEnhanceKeepsSizeAndTransparency() throws {
        let b = RasterBuffer(width: 64, height: 64, colorSpace: srgb)!
        b.fill(CGColor(srgbRed: 0.3, green: 0.25, blue: 0.2, alpha: 1), in: CGRect(x: 0, y: 0, width: 64, height: 32))
        let out = try SmartImageOps.autoEnhanced(b.copyImage()!, colorSpace: srgb)
        XCTAssertEqual(out.width, 64)
        XCTAssertEqual(out.height, 64)
        XCTAssertEqual(px(out, 10, 50)[3], 0, "transparent area stays transparent")
        XCTAssertEqual(px(out, 10, 10)[3], 255)
    }

    func testAutoEnhanceIsOneUndoStep() async throws {
        let c = canvas(try samplePhoto())
        let before = c.layers[0].buffer.copyImage()!
        c.undoManager?.beginUndoGrouping()
        try await c.autoEnhanceActiveLayer(actionName: "Auto Enhance")
        c.undoManager?.endUndoGrouping()
        XCTAssertEqual(c.undoManager?.undoActionName, "Auto Enhance")
        c.undoManager?.undo()
        XCTAssertEqual(px(c.layers[0].buffer.copyImage()!, 100, 100), px(before, 100, 100))
    }

    // MARK: Subject (Vision)

    func testRemoveBackgroundClearsCornersKeepsSubjectAndUndoes() async throws {
        let c = canvas(try samplePhoto())
        c.undoManager?.beginUndoGrouping()
        try await c.removeBackground(actionName: "Remove Background")
        c.undoManager?.endUndoGrouping()
        let out = c.layers[0].buffer.copyImage()!
        XCTAssertEqual(px(out, out.width - 3, 2)[3], 0, "background corner became transparent")
        XCTAssertEqual(px(out, out.width / 2, out.height / 2)[3], 255, "subject centre is kept")
        XCTAssertEqual(c.layers.count, 1)
        c.undoManager?.undo()
        XCTAssertEqual(px(c.layers[0].buffer.copyImage()!, out.width - 3, 2)[3], 255, "undo restores the background")
    }

    func testCopySubjectAddsLayerAboveActive() async throws {
        let c = canvas(try samplePhoto())
        c.undoManager?.beginUndoGrouping()
        try await c.copySubjectToNewLayer(name: "Subject", actionName: "Copy Subject")
        c.undoManager?.endUndoGrouping()
        XCTAssertEqual(c.layers.count, 2)
        XCTAssertEqual(c.activeLayer?.name, "Subject")
        XCTAssertEqual(c.activeLayerIndex, 1)
        let top = c.layers[1].buffer.copyImage()!
        XCTAssertEqual(px(top, 2, 2)[3], 0)
        XCTAssertEqual(px(c.layers[0].buffer.copyImage()!, 2, 2)[3], 255, "original layer untouched")
        c.undoManager?.undo()
        XCTAssertEqual(c.layers.count, 1)
    }

    func testRemoveBackgroundOnBlankImageReportsNoSubject() async throws {
        let c = canvas(solidImage(256, 256, [128, 128, 128, 255]))
        do {
            try await c.removeBackground(actionName: "t")
            XCTFail("a flat grey image has no subject")
        } catch let error as SmartImageOps.Failure {
            XCTAssertEqual(error, .noSubject)
        }
        XCTAssertEqual(c.undoManager?.canUndo, false, "nothing changed")
    }

    func testStaleResultIsRejected() async throws {
        let c = canvas(try samplePhoto())
        // groupsByEvent is off: every undo registration needs an explicit group (else AppKit raises).
        let task = Task { () -> Error? in
            do { try await c.removeBackground(actionName: "t"); return nil } catch { return error }
        }
        await Task.yield()   // let the edit take its snapshot and start the analysis
        // Paint while the analysis runs (the region edit bumps the layer revision).
        c.undoManager?.beginUndoGrouping()
        c.applyRegionEdit(layerID: c.layers[0].id, rect: CGRect(x: 0, y: 0, width: 4, height: 4), actionName: "p") { ctx in
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        c.undoManager?.endUndoGrouping()
        let error = await task.value
        XCTAssertEqual(error as? CanvasModel.EditError, .canvasChanged, "stale result must not be installed")
        XCTAssertEqual(px(c.layers[0].buffer.copyImage()!, c.width - 3, 2)[3], 255, "background untouched")
    }

    // MARK: Settings / menus

    func testToolPalettePositionDefaultsToTopAndPersists() {
        let suite = "DosPhotoPaint.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let s = AppSettings(defaults: d)
        XCTAssertEqual(s.paintToolPalettePosition, .top)
        s.paintToolPalettePosition = .left
        XCTAssertEqual(AppSettings(defaults: d).paintToolPalettePosition, .left)
        s.resetToDefaults()
        XCTAssertEqual(s.paintToolPalettePosition, .top)
    }

    func testSmartEditAndBackgroundMenusAreWired() {
        let smart = MainWindowController.smartEditMenu().items.compactMap(\.action)
        XCTAssertEqual(Set(smart), [#selector(AppActions.removeBackground(_:)), #selector(AppActions.copySubjectToNewLayer(_:)),
                                    #selector(AppActions.autoEnhance(_:))])
        for action in smart { XCTAssertTrue(MainWindowController.instancesRespond(to: action)) }
        let bg = MainWindowController.viewerBackgroundMenu().items
        XCTAssertEqual(bg.count, ViewerBackgroundSetting.allCases.count)
        XCTAssertEqual(bg.map(\.tag), Array(ViewerBackgroundSetting.allCases.indices))
    }
}
