import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DosPhotoPaint

/// End-to-end tests that drive the REAL app objects inside the test host: `DocumentController`,
/// `ImageDocument`, `MainWindowController`, `CanvasView` with synthesized `NSEvent`s, the tools,
/// undo and saving. No mocks. Also renders window screenshots (see `testScreenshots`).
@MainActor
final class IntegrationTests: AppTestCase {
    private static var dir: URL!
    private var dir: URL { Self.dir }

    // MARK: - Fixtures

    private static let hole = CGRect(x: 160, y: 0, width: 80, height: 80)   // transparent area of the PNG
    private static let redSquare = CGRect(x: 10, y: 10, width: 20, height: 20)

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            Self.dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("dpp-integration-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            Self.closeAllDocuments()
            Self.resetToolSettings()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            Self.closeAllDocuments()
            try? FileManager.default.removeItem(at: Self.dir)
        }
        super.tearDown()
    }

    private static func closeAllDocuments() {
        for doc in DocumentController.shared.documents {
            doc.updateChangeCount(.changeCleared)
            doc.close()
        }
    }

    private static func resetToolSettings() {
        let t = ToolSettings.shared
        t.tool = .pen
        t.primaryColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        t.secondaryColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        t.opacity = 1
        t.penWidth = 3
        t.brushSize = 12
        t.brushHardness = 0.8
        t.brushType = .round
        t.eraserSize = 16
        t.eraserMode = .transparent
        t.fillTolerance = 32
        t.fillContiguous = true
        t.shapeKind = .rectangle
        t.shapeStrokeEnabled = true
        t.shapeFillEnabled = false
        t.shapeLineWidth = 2
        t.fontSize = 32
        t.bold = false
        t.italic = false
        t.underline = false
        t.transparentSelection = false
        t.cropAspect = .free
    }

    private func rgbaContext(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private func write(_ image: CGImage, type: UTType, to url: URL, properties: [CFString: Any] = [:]) throws {
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    /// 240×160 opaque light gray, a transparent hole top-right, a red square top-left.
    private func makeAlphaPNG(name: String = "a_alpha.png") throws -> URL {
        let ctx = rgbaContext(240, 160)
        ctx.setFillColor(CGColor(srgbRed: 200 / 255, green: 200 / 255, blue: 200 / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        ctx.clear(CGRect(x: Self.hole.minX, y: 160 - Self.hole.maxY, width: Self.hole.width, height: Self.hole.height))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: Self.redSquare.minX, y: 160 - Self.redSquare.maxY, width: 20, height: 20))
        let url = dir.appendingPathComponent(name)
        try write(ctx.makeImage()!, type: .png, to: url)
        return url
    }

    /// Stored 300×200 (left half red, right half green) with EXIF orientation 6 → upright 200×300:
    /// top half red, bottom half green.
    private func makeExifJPEG(name: String = "b_exif.jpg") throws -> URL {
        let ctx = rgbaContext(300, 200)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 150, height: 200))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 150, y: 0, width: 150, height: 200))
        let url = dir.appendingPathComponent(name)
        try write(ctx.makeImage()!, type: .jpeg, to: url,
                  properties: [kCGImagePropertyOrientation: 6, kCGImageDestinationLossyCompressionQuality: 0.95])
        return url
    }

    private func makeBigJPEG(name: String = "big.jpg") throws -> URL {
        let ctx = rgbaContext(6000, 4000)
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 6000, height: 4000))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 3000, width: 1000, height: 1000))   // top-left in image space
        let url = dir.appendingPathComponent(name)
        try write(ctx.makeImage()!, type: .jpeg, to: url, properties: [kCGImageDestinationLossyCompressionQuality: 0.5])
        return url
    }

    private func makeGIF(name: String = "c_anim.gif") throws -> URL {
        let url = dir.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil))
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<3 {
            let ctx = rgbaContext(64, 48)
            ctx.setFillColor(CGColor(srgbRed: i == 0 ? 1 : 0, green: i == 1 ? 1 : 0, blue: i == 2 ? 1 : 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            CGImageDestinationAddImage(dest, ctx.makeImage()!,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }


    private func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Driving the app

    private func waitUntil(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))   // polling the condition, not a fixed delay
        }
        XCTAssertTrue(condition(), "Timed out waiting for: \(what)")
    }

    /// AppKit groups undo registrations per event: the group opens when the first registration of an
    /// event happens and closes when the event is done (which also makes NSDocument update its change
    /// count). That machinery lives in `NSApplication`'s event loop, which does not run in a test host,
    /// so each "event" is bracketed explicitly: `beginEventCycle()` … `endEventCycle()`.
    private func beginEventCycle() {
        for doc in DocumentController.shared.documents {
            guard let um = doc.undoManager else { continue }
            um.groupsByEvent = false
            if um.groupingLevel == 0, (doc as? ImageDocument)?.isMaterialized == true { um.beginUndoGrouping() }
        }
    }

    private func endEventCycle() {
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        for doc in DocumentController.shared.documents {
            guard let um = doc.undoManager else { continue }
            while um.groupingLevel > 0 { um.endUndoGrouping() }
        }
    }

    /// Text views keep their own undo manager; give it its per-event group like a run-loop wake-up would.
    private func beginEvent(for tv: NSTextView) { tv.undoManager?.beginUndoGrouping() }

    private func mainWindowControllers() -> [MainWindowController] {
        DocumentController.shared.documents.flatMap(\.windowControllers).compactMap { $0 as? MainWindowController }
    }

    /// Opens through the Finder entry point and waits until the window shows its content.
    @discardableResult
    private func open(_ urls: [URL], file: StaticString = #filePath, line: UInt = #line) async throws -> (wc: MainWindowController, doc: ImageDocument) {
        var results: [URL: NSDocument] = [:]
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DocumentController.shared.openForViewing(urls) { results = $0; c.resume() }
        }
        guard let doc = results.values.first as? ImageDocument,
              let wc = doc.windowControllers.first as? MainWindowController else {
            XCTFail("Document did not open", file: file, line: line)
            throw XCTSkip("open failed")
        }
        await waitUntil("preview of \(wc.imageDocument?.fileURL?.lastPathComponent ?? "?")") {
            if case .none = wc.canvasView.content { return false }
            return true
        }
        return (wc, doc)
    }

    /// Opens an image and switches to Paint Mode.
    private func openPaint(_ url: URL) async throws -> (wc: MainWindowController, doc: ImageDocument, model: CanvasModel) {
        let (wc, doc) = try await open([url])
        await enterPaint(wc)
        let model = doc.canvas!
        wc.window?.contentView?.layoutSubtreeIfNeeded()
        return (wc, doc, model)
    }

    private func enterPaint(_ wc: MainWindowController) async {
        await wc.enterPaintMode()
        XCTAssertEqual(wc.state.mode, .paint)
        endEventCycle()
    }

    private func applyEdit(_ model: CanvasModel, _ edit: ImageEdit) async {
        beginEventCycle()
        do { try await model.apply(edit, actionName: "Test edit") } catch { XCTFail("edit failed: \(error)") }
        endEventCycle()
    }

    private func isPreview(_ c: CanvasContent) -> Bool {
        if case .preview = c { return true }
        return false
    }

    // Events -------------------------------------------------------------------------

    private func mouseEvent(_ type: NSEvent.EventType, at canvasPoint: CGPoint, in wc: MainWindowController,
                            flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) -> NSEvent {
        let p = wc.canvasView.convert(canvasPoint, to: nil)
        return NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: wc.window!.windowNumber, context: nil, eventNumber: 0,
                                  clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    /// Mouse down at the first point, drags through the rest, mouse up at the last.
    private func drag(_ points: [CGPoint], in wc: MainWindowController, flags: NSEvent.ModifierFlags = [], clickCount: Int = 1,
                      registersUndo: Bool = true) {
        if registersUndo { beginEventCycle() }
        let v = wc.canvasView
        v.mouseDown(with: mouseEvent(.leftMouseDown, at: points[0], in: wc, flags: flags, clickCount: clickCount))
        for p in points.dropFirst() { v.mouseDragged(with: mouseEvent(.leftMouseDragged, at: p, in: wc, flags: flags)) }
        v.mouseUp(with: mouseEvent(.leftMouseUp, at: points.last!, in: wc, flags: flags))
        endEventCycle()   // gestures that do not register undo must not open a group (it would count as a step)
    }

    private func click(_ p: CGPoint, in wc: MainWindowController, flags: NSEvent.ModifierFlags = [], registersUndo: Bool = true) {
        if registersUndo { beginEventCycle() }
        let v = wc.canvasView
        v.mouseDown(with: mouseEvent(.leftMouseDown, at: p, in: wc, flags: flags))
        v.mouseUp(with: mouseEvent(.leftMouseUp, at: p, in: wc, flags: flags))
        endEventCycle()
    }

    private func pressReturn(in wc: MainWindowController) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: wc.window!.windowNumber, context: nil, characters: "\r",
                                 charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        beginEventCycle()
        wc.canvasView.keyDown(with: e)
        endEventCycle()
    }

    // Pixels -------------------------------------------------------------------------

    typealias Pixel = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    private func px(_ model: CanvasModel, _ x: Int, _ y: Int, layer: Int = 0) -> Pixel {
        model.layers[layer].buffer.pixel(x: x, y: y) ?? (0, 0, 0, 0)
    }

    private func isColor(_ p: Pixel, _ r: Int, _ g: Int, _ b: Int, tol: Int = 12) -> Bool {
        p.a == 255 && abs(Int(p.r) - r) <= tol && abs(Int(p.g) - g) <= tol && abs(Int(p.b) - b) <= tol
    }

    private func bytes(_ model: CanvasModel, layer: Int = 0) -> Data {
        let b = model.layers[layer].buffer
        return b.withMutablePixels { p, bpr in Data(bytes: p, count: bpr * b.height) } ?? Data()
    }

    /// Pixel bounding box where two same-size layer dumps differ.
    private func diffBounds(_ a: Data, _ b: Data, model: CanvasModel) -> CGRect? {
        let bpr = model.layers[0].buffer.bytesPerRow
        guard a.count == b.count else { return nil }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        a.withUnsafeBytes { pa in
            b.withUnsafeBytes { pb in
                for y in 0..<model.height {
                    for x in 0..<model.width {
                        let o = y * bpr + x * 4
                        if pa[o] != pb[o] || pa[o + 1] != pb[o + 1] || pa[o + 2] != pb[o + 2] || pa[o + 3] != pb[o + 3] {
                            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                        }
                    }
                }
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Undo/redo like the Edit menu: the open per-event group is closed first (AppKit does that itself).
    private func undo(_ doc: ImageDocument) {
        while doc.undoManager!.groupingLevel > 0 { doc.undoManager!.endUndoGrouping() }
        doc.undoManager!.undo()
        endEventCycle()
    }

    private func redo(_ doc: ImageDocument) {
        while doc.undoManager!.groupingLevel > 0 { doc.undoManager!.endUndoGrouping() }
        doc.undoManager!.redo()
        endEventCycle()
    }

    private func undoStack(_ doc: ImageDocument) -> UndoManager { doc.undoManager! }

    /// Undoes everything and returns how many steps that took.
    @discardableResult
    private func undoAll(_ doc: ImageDocument) -> Int {
        var n = 0
        while doc.undoManager!.canUndo, n < 50 {
            undo(doc)
            n += 1
        }
        return n
    }

    private func decode(_ url: URL) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let img = try ImageLoader.loadFullImage(url: url).image
        let ctx = rgbaContext(img.width, img.height)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let flipped = Array(UnsafeBufferPointer(start: data, count: ctx.bytesPerRow * img.height))
        return (flipped, img.width, img.height)   // CGBitmapContext rows are top-down in memory
    }

    // MARK: - 2. Open for viewing (Photo Mode, lazy)

    func testOpenEachFormatInPhotoModeWithoutTouchingOriginal() async throws {
        let fixtures: [(URL, CGSize)] = [
            (try makeAlphaPNG(), CGSize(width: 240, height: 160)),
            (try makeExifJPEG(), CGSize(width: 200, height: 300)),
            (try makeBigJPEG(), CGSize(width: 6000, height: 4000)),
            (try makeGIF(), CGSize(width: 64, height: 48)),
        ]
        for (url, size) in fixtures {
            let before = try sha(url)
            let (wc, doc) = try await open([url])
            XCTAssertEqual(mainWindowControllers().count, 1, url.lastPathComponent)
            XCTAssertEqual(doc.windowControllers.count, 1)
            XCTAssertEqual(wc.state.mode, .photo)
            XCTAssertFalse(doc.isMaterialized, "viewing must not materialize \(url.lastPathComponent)")
            XCTAssertNil(doc.canvas)
            await waitUntil("preview content") { self.isPreview(wc.canvasView.content) }
            if case .preview(let image, let pixelSize) = wc.canvasView.content {
                XCTAssertEqual(pixelSize, size, "upright pixel size of \(url.lastPathComponent)")
                XCTAssertGreaterThan(image.width, 0)
                XCTAssertLessThanOrEqual(max(image.width, image.height), max(wc.displayPixelBudget(), Int(max(size.width, size.height))))
            }
            XCTAssertFalse(doc.isDocumentEdited)
            XCTAssertEqual(try sha(url), before, "opening must not modify \(url.lastPathComponent)")
            Self.closeAllDocuments()
            XCTAssertEqual(mainWindowControllers().count, 0, "window closes with its document")
        }
    }

    // MARK: - EXIF orientation consistency (Photo preview vs editable canvas)

    func testAllEXIFOrientationsDecodeLikeImageIO() async throws {
        // Stored 30×20: TL red, TR green, BL blue, BR yellow.
        let ctx = rgbaContext(30, 20)
        let quads: [(CGRect, (CGFloat, CGFloat, CGFloat))] = [
            (CGRect(x: 0, y: 10, width: 15, height: 10), (1, 0, 0)), (CGRect(x: 15, y: 10, width: 15, height: 10), (0, 1, 0)),
            (CGRect(x: 0, y: 0, width: 15, height: 10), (0, 0, 1)), (CGRect(x: 15, y: 0, width: 15, height: 10), (1, 1, 0)),
        ]
        for (r, c) in quads { ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)); ctx.fill(r) }
        let image = ctx.makeImage()!
        func sampleQuadrants(_ img: CGImage) -> [String] {
            let c = rgbaContext(img.width, img.height)
            c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            let p = c.data!.assumingMemoryBound(to: UInt8.self)
            return [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)].map { fx, fy in
                let x = Int(Double(img.width) * fx), y = Int(Double(img.height) * fy)
                let o = y * c.bytesPerRow + x * 4
                func q(_ v: UInt8) -> Int { v > 160 ? 1 : 0 }
                return "\(q(p[o]))\(q(p[o + 1]))\(q(p[o + 2]))"
            }
        }
        for o in 1...8 {
            let url = dir.appendingPathComponent("orient\(o).tiff")
            try write(image, type: .tiff, to: url, properties: [kCGImagePropertyOrientation: o])
            let editable = try ImageLoader.loadFullImage(url: url).image
            let preview = try ImageLoader.loadDisplayImage(url: url, maxPixelSize: 60)
            XCTAssertEqual(editable.width * preview.height, editable.height * preview.width, "orientation \(o): aspect")
            XCTAssertEqual(sampleQuadrants(editable), sampleQuadrants(preview), "orientation \(o): the editable canvas must match the Photo Mode preview")
        }
    }

    // MARK: - 3. Photo ⇄ Paint

    func testPaintModeMaterializesUprightAndKeepsZoomAndCanvas() async throws {
        let exif = try makeExifJPEG()
        let big = try makeBigJPEG()
        for (url, size, zoom) in [(exif, CGSize(width: 200, height: 300), CGFloat(1.5)),
                                  (big, CGSize(width: 6000, height: 4000), CGFloat(0.3))] {
            let before = try sha(url)
            let (wc, doc) = try await open([url])
            wc.scrollView.setZoom(zoom)
            let z0 = wc.scrollView.magnification
            XCTAssertEqual(z0, zoom, accuracy: 0.001)

            await enterPaint(wc)
            let model = try XCTUnwrap(doc.canvas, "canvas must exist after entering Paint")
            XCTAssertEqual(model.size, size, "materialized size must be the upright size")
            XCTAssertEqual(wc.state.mode, .paint)
            XCTAssertEqual(wc.scrollView.magnification, z0, accuracy: 0.0001, "zoom must survive Photo→Paint (\(url.lastPathComponent))")
            guard case .canvas(let shown) = wc.canvasView.content else { return XCTFail("canvas content expected") }
            XCTAssertTrue(shown === model)
            XCTAssertFalse(doc.isDocumentEdited, "entering Paint is not an edit")
            XCTAssertFalse(doc.undoManager?.canUndo ?? false)

            if url == exif {
                // Orientation 6: top half red, bottom half green after upright decoding.
                XCTAssertTrue(isColor(px(model, 100, 20), 255, 0, 0, tol: 40), "upright top must be red, got \(px(model, 100, 20)) / left \(px(model, 20, 150)) right \(px(model, 180, 150))")
                XCTAssertTrue(isColor(px(model, 100, 280), 0, 255, 0, tol: 40), "upright bottom must be green")
            } else {
                XCTAssertTrue(isColor(px(model, 100, 100), 255, 204, 0, tol: 25), "top-left of big image is yellow")
                XCTAssertTrue(isColor(px(model, 3000, 2000), 51, 102, 204, tol: 25))
            }

            wc.setMode(.photo)
            XCTAssertEqual(wc.state.mode, .photo)
            XCTAssertEqual(wc.scrollView.magnification, z0, accuracy: 0.0001, "zoom must survive Paint→Photo")
            guard case .canvas(let again) = wc.canvasView.content else { return XCTFail("canvas must stay shown in Photo Mode") }
            XCTAssertTrue(again === model, "switching back must not reload the canvas")
            XCTAssertTrue(doc.canvas === model)

            await enterPaint(wc)
            XCTAssertTrue(doc.canvas === model, "re-entering Paint must not rematerialize")
            XCTAssertEqual(wc.scrollView.magnification, z0, accuracy: 0.0001)
            XCTAssertEqual(try sha(url), before, "mode switching must not modify the original")
            Self.closeAllDocuments()
        }
    }

    func testAnimatedGIFEntersPaintAsFirstFrame() async throws {
        let url = try makeGIF()
        let before = try sha(url)
        let (wc, doc) = try await open([url])
        XCTAssertTrue(doc.isAnimated)
        // The "animation flattened" notice is a sheet; it must not block (sheets are non-modal).
        await enterPaint(wc)
        let model = try XCTUnwrap(doc.canvas)
        XCTAssertEqual(model.size, CGSize(width: 64, height: 48))
        XCTAssertTrue(isColor(px(model, 10, 10), 255, 0, 0, tol: 40), "first frame is red")
        if let sheet = wc.window?.attachedSheet { wc.window?.endSheet(sheet) }
        XCTAssertEqual(try sha(url), before)
    }

    // MARK: - 4. Pen through real events at several magnifications

    func testPenEventsMapToPixelsAtSeveralZoomLevels() async throws {
        let url = try makeAlphaPNG()
        let before = try sha(url)
        let (wc, doc, model) = try await openPaint(url)
        ToolSettings.shared.tool = .pen
        wc.activateTool(.pen)
        XCTAssertNotNil(wc.activeTool as? StrokeTool)
        let sv = wc.scrollView
        XCTAssertTrue(model.undoManager === doc.undoManager)

        let colors: [(CGFloat, NSColor, (Int, Int, Int))] = [
            (1, NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), (255, 0, 0)),
            (0.5, NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), (0, 255, 0)),
            (4, NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), (0, 0, 255)),
        ]
        for (zoom, color, rgb) in colors {
            ToolSettings.shared.primaryColor = color
            sv.setZoom(zoom)
            sv.scrollToCenter()
            wc.window?.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(sv.magnification, zoom, accuracy: 0.0001)

            // Geometry sanity of the mapping: y is down, scale equals the magnification.
            let a = wc.canvasView.convert(CGPoint(x: 90, y: 60), to: nil)
            let b = wc.canvasView.convert(CGPoint(x: 190, y: 160), to: nil)
            XCTAssertEqual(b.x - a.x, 100 * zoom, accuracy: 0.01)
            XCTAssertEqual(a.y - b.y, 100 * zoom, accuracy: 0.01, "canvas y grows downwards in window coordinates")

            let p0 = CGPoint(x: 90, y: 60), p1 = CGPoint(x: 150, y: 60), p2 = CGPoint(x: 150, y: 100)
            for p in [p0, p1, p2] {
                XCTAssertTrue(wc.canvasView.visibleRect.contains(p), "test point \(p) must be visible at zoom \(zoom)")
            }
            let baseline = bytes(model)
            XCTAssertFalse(doc.undoManager!.canUndo)
            drag([p0, CGPoint(x: 120, y: 60), p1, CGPoint(x: 150, y: 80), p2], in: wc)

            XCTAssertTrue(isColor(px(model, 120, 60), rgb.0, rgb.1, rgb.2), "zoom \(zoom): middle of horizontal segment")
            XCTAssertTrue(isColor(px(model, 120, 59), rgb.0, rgb.1, rgb.2), "zoom \(zoom): width covers row above")
            XCTAssertTrue(isColor(px(model, 150, 80), rgb.0, rgb.1, rgb.2), "zoom \(zoom): middle of vertical segment")
            XCTAssertTrue(isColor(px(model, 90, 60), rgb.0, rgb.1, rgb.2, tol: 40), "zoom \(zoom): start point")
            XCTAssertTrue(isColor(px(model, 150, 100), rgb.0, rgb.1, rgb.2, tol: 40), "zoom \(zoom): end point")
            for (x, y) in [(120, 100), (90, 100), (90, 80), (120, 40), (120, 75), (170, 80)] {
                XCTAssertTrue(isColor(px(model, x, y), 200, 200, 200), "zoom \(zoom): (\(x),\(y)) must be untouched, got \(px(model, x, y))")
            }
            let drawn = bytes(model)
            let box = try XCTUnwrap(diffBounds(baseline, drawn, model: model))
            XCTAssertEqual(box.minX, 88, accuracy: 3, "zoom \(zoom)")
            XCTAssertEqual(box.minY, 58, accuracy: 3)
            XCTAssertEqual(box.maxX, 152, accuracy: 3)
            XCTAssertEqual(box.maxY, 102, accuracy: 3)
            XCTAssertTrue(doc.isDocumentEdited)

            // One stroke = one undo step.
            let um = doc.undoManager!
            XCTAssertTrue(um.canUndo)
            undo(doc)
            XCTAssertEqual(bytes(model), baseline, "zoom \(zoom): undo must restore exact pixels")
            XCTAssertFalse(um.canUndo, "zoom \(zoom): exactly one undo step per stroke")
            XCTAssertTrue(um.canRedo)
            redo(doc)
            XCTAssertEqual(bytes(model), drawn, "zoom \(zoom): redo must re-apply exact pixels")
            undo(doc)
            XCTAssertFalse(um.canUndo)
        }
        XCTAssertEqual(try sha(url), before)
    }

    // MARK: - 5. Tools

    func testBrushAndEraser() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        let t = ToolSettings.shared
        t.primaryColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        wc.activateTool(.brush)
        var base = bytes(model)
        drag([CGPoint(x: 60, y: 100), CGPoint(x: 90, y: 100), CGPoint(x: 120, y: 100)], in: wc)
        XCTAssertTrue(isColor(px(model, 90, 100), 0, 0, 255, tol: 20), "brush core is the primary colour, got \(px(model, 90, 100))")
        XCTAssertTrue(isColor(px(model, 90, 130), 200, 200, 200))
        var box = try XCTUnwrap(diffBounds(base, bytes(model), model: model))
        XCTAssertEqual(box.midX, 90, accuracy: 4); XCTAssertEqual(box.midY, 100, accuracy: 3)
        XCTAssertEqual(undoAll(doc), 1, "brush stroke = one undo step")
        XCTAssertEqual(bytes(model), base)

        wc.activateTool(.eraser)
        base = bytes(model)
        drag([CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 100)], in: wc)
        XCTAssertEqual(px(model, 90, 100).a, 0, "eraser makes pixels transparent")
        XCTAssertTrue(isColor(px(model, 90, 130), 200, 200, 200))
        box = try XCTUnwrap(diffBounds(base, bytes(model), model: model))
        XCTAssertEqual(box.midX, 90, accuracy: 12); XCTAssertEqual(box.midY, 100, accuracy: 3)
        XCTAssertEqual(undoAll(doc), 1, "eraser stroke = one undo step")
        XCTAssertEqual(bytes(model), base)
    }

    func testFillAndEyedropper() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        let t = ToolSettings.shared
        t.primaryColor = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        wc.activateTool(.fill)
        let base = bytes(model)
        click(CGPoint(x: 60, y: 100), in: wc)
        XCTAssertTrue(isColor(px(model, 60, 100), 0, 255, 0), "fill colours the clicked region, got \(px(model, 60, 100))")
        XCTAssertTrue(isColor(px(model, 200, 150), 0, 255, 0), "contiguous gray region is filled everywhere")
        XCTAssertEqual(px(model, 200, 20).a, 0, "transparent hole is a different region")
        XCTAssertTrue(isColor(px(model, 15, 15), 255, 0, 0), "red square is a barrier")
        XCTAssertEqual(undoAll(doc), 1, "fill = one undo step")
        XCTAssertEqual(bytes(model), base)

        t.primaryColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        wc.activateTool(.eyedropper)
        click(CGPoint(x: 15, y: 15), in: wc, registersUndo: false)
        let picked = try XCTUnwrap(t.primaryColor.usingColorSpace(.sRGB))
        XCTAssertEqual(picked.redComponent, 1, accuracy: 0.02)
        XCTAssertEqual(picked.greenComponent, 0, accuracy: 0.02)
        XCTAssertEqual(picked.blueComponent, 0, accuracy: 0.02)
        XCTAssertFalse(doc.undoManager!.canUndo, "picking colours is not undoable")
        XCTAssertEqual(bytes(model), base)
        click(CGPoint(x: 60, y: 100), in: wc, flags: .option, registersUndo: false)
        let secondary = try XCTUnwrap(t.secondaryColor.usingColorSpace(.sRGB))
        XCTAssertEqual(secondary.redComponent, 200.0 / 255, accuracy: 0.02, "option-click picks the secondary colour")
    }

    func testShapeRectangleWithShiftIsSquare() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        ToolSettings.shared.primaryColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        wc.activateTool(.shape)
        ToolSettings.shared.shapeKind = .rectangle
        let base = bytes(model)
        drag([CGPoint(x: 60, y: 40), CGPoint(x: 100, y: 55), CGPoint(x: 140, y: 70)], in: wc, flags: .shift)
        let box = try XCTUnwrap(diffBounds(base, bytes(model), model: model))
        XCTAssertEqual(box.width, box.height, accuracy: 3, "Shift constrains the rectangle to a square, got \(box)")
        XCTAssertEqual(box.minX, 59, accuracy: 3)
        XCTAssertEqual(box.minY, 39, accuracy: 3)
        XCTAssertGreaterThan(box.width, 60, "the longer drag axis defines the side")
        XCTAssertTrue(isColor(px(model, 100, 40), 0, 0, 255, tol: 40), "top edge")
        XCTAssertTrue(isColor(px(model, 60, 60), 0, 0, 255, tol: 40), "left edge")
        XCTAssertTrue(isColor(px(model, 100, 80), 200, 200, 200), "interior stays unfilled")
        XCTAssertEqual(undoAll(doc), 1)
        XCTAssertEqual(bytes(model), base)

        // Without Shift the same drag gives the exact 80×30 rectangle.
        drag([CGPoint(x: 60, y: 40), CGPoint(x: 140, y: 70)], in: wc)
        let free = try XCTUnwrap(diffBounds(base, bytes(model), model: model))
        XCTAssertEqual(free.width, 82, accuracy: 3); XCTAssertEqual(free.height, 32, accuracy: 3)
        undoAll(doc)
    }

    func testTextToolWithRealTextViewAndIME() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        let t = ToolSettings.shared
        t.primaryColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)

        // An earlier stroke must survive the text edit in the undo history.
        wc.activateTool(.pen)
        drag([CGPoint(x: 20, y: 140), CGPoint(x: 60, y: 140)], in: wc)
        let afterStroke = bytes(model)

        wc.activateTool(.text)
        let tool = try XCTUnwrap(wc.activeTool as? TextTool)
        drag([CGPoint(x: 20, y: 60), CGPoint(x: 140, y: 110)], in: wc, registersUndo: false)
        let tv = try XCTUnwrap(tool.textView, "dragging with the text tool creates a text box")
        XCTAssertTrue(wc.window?.firstResponder === tv, "the new box must take keyboard focus immediately")
        XCTAssertEqual(tool.box, CGRect(x: 20, y: 60, width: 120, height: 50))

        beginEvent(for: tv)
        tv.insertText("A", replacementRange: NSRange(location: NSNotFound, length: 0))
        // IME composition: marked text first, then the final conversion replaces it.
        tv.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(tv.hasMarkedText())
        XCTAssertFalse(tool.commit(force: false), "while composing, commit must wait for the IME")
        XCTAssertNotNil(tool.textView, "box stays open while composing")
        tv.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(tv.hasMarkedText())
        XCTAssertEqual(tv.string, "A日本")

        beginEventCycle()
        XCTAssertTrue(tool.commit(force: false))
        endEventCycle()
        XCTAssertTrue(tool.textView == nil, "text box closed after commit")
        let box = try XCTUnwrap(diffBounds(afterStroke, bytes(model), model: model))
        XCTAssertTrue(CGRect(x: 20, y: 60, width: 120, height: 50).insetBy(dx: -2, dy: -2).contains(box), "text pixels stay inside the box: \(box)")
        XCTAssertGreaterThan(box.width, 20)
        // Blue text on gray.
        var blueish = 0
        for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) where Int(px(model, x, y).b) > Int(px(model, x, y).r) + 60 { blueish += 1 } }
        XCTAssertGreaterThan(blueish, 30, "rendered glyphs use the primary colour")

        undo(doc)
        XCTAssertEqual(bytes(model), afterStroke, "undo removes the whole text in one step")
        XCTAssertTrue(doc.undoManager!.canUndo, "the earlier stroke is still in the history")
        XCTAssertEqual(undoAll(doc), 1)
    }

    func testRectangleSelectMoveCommitUndo() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        // Distinct source content (setup, not an edit).
        model.layers[0].buffer.fill(CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1), in: CGRect(x: 40, y: 30, width: 40, height: 30))
        model.invalidateAll()
        let base = bytes(model)
        wc.activateTool(.rectangleSelect)
        drag([CGPoint(x: 40, y: 30), CGPoint(x: 60, y: 50), CGPoint(x: 80, y: 60)], in: wc)
        XCTAssertEqual(model.selection?.bounds, CGRect(x: 40, y: 30, width: 40, height: 30))
        drag([CGPoint(x: 60, y: 45), CGPoint(x: 90, y: 70), CGPoint(x: 120, y: 95)], in: wc)
        XCTAssertNotNil(model.floating, "dragging inside the selection lifts it")
        pressReturn(in: wc)
        XCTAssertNil(model.floating, "Return commits the floating selection")
        XCTAssertTrue(isColor(px(model, 110, 85), 255, 255, 0), "moved content lands at +60,+50, got \(px(model, 110, 85))")
        XCTAssertFalse(isColor(px(model, 60, 45), 255, 255, 0), "source area no longer holds the content")
        XCTAssertTrue(isColor(px(model, 130, 105), 255, 255, 0), "far corner of the moved block")
        XCTAssertFalse(isColor(px(model, 142, 106), 255, 255, 0))
        let steps = undoAll(doc)
        XCTAssertLessThanOrEqual(steps, 3, "select + move/commit must stay a handful of steps")
        XCTAssertGreaterThanOrEqual(steps, 1)
        XCTAssertEqual(bytes(model), base, "undo restores the exact pixels")
        XCTAssertNil(model.selection)
    }

    func testCropToolAndUndo() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        let base = bytes(model)
        wc.activateTool(.crop)
        drag([CGPoint(x: 40, y: 30), CGPoint(x: 90, y: 60), CGPoint(x: 140, y: 110)], in: wc, registersUndo: false)
        beginEventCycle()
        wc.applyCrop(nil)
        endEventCycle()
        XCTAssertEqual(model.size, CGSize(width: 100, height: 80))
        XCTAssertEqual(wc.state.imageSize, CGSize(width: 100, height: 80))
        XCTAssertEqual(wc.canvasView.frame.size, CGSize(width: 100, height: 80), "view follows the new size")
        XCTAssertTrue(isColor(px(model, 0, 0), 200, 200, 200))
        XCTAssertEqual(undoAll(doc), 1, "crop = one undo step")
        XCTAssertEqual(model.size, CGSize(width: 240, height: 160))
        XCTAssertEqual(wc.canvasView.frame.size, CGSize(width: 240, height: 160))
        XCTAssertEqual(bytes(model), base)
    }

    func testRotateRightFourTimesIsIdentityAndResizeUndo() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        let base = bytes(model)
        let expected = [CGSize(width: 160, height: 240), CGSize(width: 240, height: 160), CGSize(width: 160, height: 240), CGSize(width: 240, height: 160)]
        for (i, size) in expected.enumerated() {
            beginEventCycle()
            wc.rotateRight(nil)
            await waitUntil("rotation \(i + 1)") { model.size == size && !wc.state.isLoading }
            await waitUntil("status size follows") { wc.state.imageSize == size }
            endEventCycle()
            if i == 0 {
                // Hole (top-right) moves to bottom-right; red square (top-left) moves to top-right.
                XCTAssertEqual(px(model, 80, 200).a, 0, "hole rotated clockwise")
                XCTAssertTrue(isColor(px(model, 145, 15), 255, 0, 0), "red square rotated clockwise")
            }
        }
        XCTAssertEqual(bytes(model), base, "four right turns are the identity")
        XCTAssertEqual(undoAll(doc), 4)
        XCTAssertEqual(bytes(model), base)

        await applyEdit(model, .resize(width: 120, height: 80, interpolation: .high))
        XCTAssertEqual(model.size, CGSize(width: 120, height: 80))
        XCTAssertEqual(wc.canvasView.frame.size, CGSize(width: 120, height: 80))
        XCTAssertTrue(isColor(px(model, 60, 60), 200, 200, 200, tol: 4))
        XCTAssertEqual(px(model, 100, 10).a, 0)
        XCTAssertEqual(undoAll(doc), 1)
        XCTAssertEqual(model.size, CGSize(width: 240, height: 160))
        XCTAssertEqual(bytes(model), base)
    }

    func testNewLayerThenMerge() async throws {
        let (wc, doc, model) = try await openPaint(try makeAlphaPNG())
        let base = bytes(model)
        beginEventCycle()
        XCTAssertTrue(model.addLayer())
        endEventCycle()
        XCTAssertEqual(model.layers.count, 2)
        XCTAssertEqual(model.activeLayerIndex, 1)
        wc.activateTool(.pen)
        drag([CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 100)], in: wc)
        XCTAssertTrue(isColor(px(model, 90, 100, layer: 1), 255, 0, 0), "stroke is on the new layer")
        XCTAssertEqual(bytes(model), base, "background layer untouched")
        XCTAssertTrue(isColor(px(model, 90, 100, layer: 0), 200, 200, 200))
        beginEventCycle()
        XCTAssertTrue(model.mergeActiveLayerDown())
        endEventCycle()
        XCTAssertEqual(model.layers.count, 1)
        XCTAssertTrue(isColor(px(model, 90, 100), 255, 0, 0), "merge bakes the stroke into the lower layer")
        undo(doc)
        XCTAssertEqual(model.layers.count, 2, "undo of merge restores both layers")
        XCTAssertTrue(isColor(px(model, 90, 100, layer: 1), 255, 0, 0))
        XCTAssertEqual(undoAll(doc), 2 + 0, "remaining: stroke and new layer")
        XCTAssertEqual(model.layers.count, 1)
        XCTAssertEqual(bytes(model), base)
    }

    // MARK: - 6. Saving and unsaved-change navigation

    func testSaveAsPNGKeepsOriginalAndWritesExpectedPixels() async throws {
        let url = try makeAlphaPNG()
        let before = try sha(url)
        let (wc, doc, model) = try await openPaint(url)
        wc.activateTool(.pen)
        drag([CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 100)], in: wc)
        XCTAssertTrue(doc.isDocumentEdited)

        let target = dir.appendingPathComponent("saved.png")
        let saved = expectation(description: "save")
        var saveError: Error?
        doc.save(to: target, ofType: UTType.png.identifier, for: .saveAsOperation) { saveError = $0; saved.fulfill() }
        await fulfillment(of: [saved], timeout: 30)
        XCTAssertNil(saveError)
        XCTAssertEqual(doc.fileURL?.lastPathComponent, "saved.png")
        XCTAssertFalse(doc.isDocumentEdited, "document is clean after saving")
        XCTAssertEqual(try sha(url), before, "Save As must never touch the original")

        let decoded = try decode(target)
        XCTAssertEqual(decoded.width, 240); XCTAssertEqual(decoded.height, 160)
        func at(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let o = y * decoded.width * 4 + x * 4
            return (decoded.pixels[o], decoded.pixels[o + 1], decoded.pixels[o + 2], decoded.pixels[o + 3])
        }
        XCTAssertEqual(at(90, 100).0, 255); XCTAssertEqual(at(90, 100).1, 0); XCTAssertEqual(at(90, 100).3, 255)
        XCTAssertEqual(at(200, 20).3, 0, "alpha is preserved")
        XCTAssertEqual(at(15, 15).0, 255)
        XCTAssertEqual(Int(at(60, 40).0), 200)
        XCTAssertEqual(decoded.pixels.count, 240 * 160 * 4)
        _ = model
    }

    /// Presses a button of the standard save sheet by position. The titles are localized (the test host
    /// follows the system language), so the order is used: Save, Don't Save, Cancel.
    private func pressSheetButton(in window: NSWindow, index: Int) -> Bool {
        guard let sheet = window.attachedSheet else { return false }
        var buttons: [NSButton] = []
        func collect(_ v: NSView) {
            if let b = v as? NSButton { buttons.append(b) }
            v.subviews.forEach(collect)
        }
        collect(sheet.contentView!)
        guard buttons.count == 3 else {
            XCTFail("unexpected sheet buttons: \(buttons.map { "\($0.title)[\($0.keyEquivalent)]" })")
            return false
        }
        // Cancel carries Escape, Don't Save carries "d" (language independent).
        let wanted = index == 2 ? "\u{1b}" : "d"
        guard let button = buttons.first(where: { $0.keyEquivalent == wanted }) else {
            XCTFail("no button with key equivalent \(wanted): \(buttons.map { "\($0.title)[\($0.keyEquivalent)]" })")
            return false
        }
        button.performClick(nil)
        return true
    }

    func testNavigationWithUnsavedChangesNeverDiscardsSilently() async throws {
        let a = try makeAlphaPNG(name: "a.png"), b = try makeAlphaPNG(name: "b.png"), c = try makeAlphaPNG(name: "c.png")
        let hashA = try sha(a)
        let (wc, doc) = try await open([a, b, c])
        XCTAssertEqual(wc.session.urls.count, 3)
        await enterPaint(wc)
        wc.activateTool(.pen)
        drag([CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 100)], in: wc)
        wc.setMode(.photo)
        XCTAssertTrue(doc.isDocumentEdited)
        let editedBytes = bytes(doc.canvas!)
        let window = try XCTUnwrap(wc.window)

        // The save/don't save/cancel sheet appears; until it is answered nothing changes.
        var finished = false
        Task { await wc.navigate(to: wc.session.urls[1]); finished = true }
        await waitUntil("unsaved-changes sheet") { window.attachedSheet != nil }
        XCTAssertFalse(finished, "navigation waits for the user's decision")
        XCTAssertTrue(wc.imageDocument === doc)
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertEqual(bytes(doc.canvas!), editedBytes)

        // Cancel: stays on the edited document.
        XCTAssertTrue(pressSheetButton(in: window, index: 2), "Cancel")
        await waitUntil("navigation task") { finished }
        XCTAssertTrue(wc.imageDocument === doc, "Cancel keeps the edited document")
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertEqual(DocumentController.shared.documents.count, 1)
        XCTAssertEqual(bytes(doc.canvas!), editedBytes)

        // Don't Save: explicit discard, then the next image shows.
        var finished2 = false
        Task { await wc.navigate(to: wc.session.urls[1]); finished2 = true }
        await waitUntil("second sheet") { window.attachedSheet != nil }
        XCTAssertTrue(pressSheetButton(in: window, index: 1), "Don't Save")
        await waitUntil("second navigation") { finished2 }
        await waitUntil("next image shown") { wc.imageDocument?.fileURL?.lastPathComponent == "b.png" }
        XCTAssertEqual(mainWindowControllers().count, 1)
        XCTAssertFalse(DocumentController.shared.documents.contains { $0 === doc }, "discarded document is closed")
        XCTAssertEqual(try sha(a), hashA, "navigating away from an edited document never writes the file")
    }

    // MARK: - 7. Multi-file sessions

    func testMultiFileSessionStepHomeEnd() async throws {
        let urls = [try makeAlphaPNG(name: "a.png"), try makeExifJPEG(name: "b.jpg"), try makeGIF(name: "c.gif")]
        let hashes = try urls.map(sha)
        let (wc, doc) = try await open(urls)
        XCTAssertEqual(mainWindowControllers().count, 1, "several files → one window")
        XCTAssertEqual(wc.session.urls.count, 3)
        XCTAssertEqual(wc.state.mode, .photo)
        let names = wc.session.urls.map(\.lastPathComponent)
        XCTAssertEqual(Set(names), ["a.png", "b.jpg", "c.gif"])
        XCTAssertEqual(doc.fileURL?.lastPathComponent, names[0])
        XCTAssertEqual(wc.state.sessionPosition?.index, 1)

        func current() -> String? { wc.imageDocument?.fileURL?.lastPathComponent }
        wc.step(1)
        await waitUntil("step to second") { current() == names[1] }
        XCTAssertEqual(wc.state.sessionPosition?.index, 2)
        await waitUntil("second preview") { self.isPreview(wc.canvasView.content) && wc.canvasView.pixelSize != .zero }
        XCTAssertEqual(mainWindowControllers().count, 1)
        XCTAssertEqual(DocumentController.shared.documents.count, 1, "clean documents are closed when navigated away")

        wc.showImage(at: 2)
        await waitUntil("End") { current() == names[2] }
        XCTAssertEqual(wc.session.position?.index, 3)
        wc.showImage(at: 0)
        await waitUntil("Home") { current() == names[0] }
        XCTAssertEqual(wc.session.position?.index, 1)
        wc.step(-1)   // wraps or stays depending on the loop setting; must not crash or leave the window
        endEventCycle()
        XCTAssertEqual(mainWindowControllers().count, 1)
        wc.showImage(at: 1)
        await waitUntil("back to second") { current() == names[1] }
        for (u, h) in zip(urls, hashes) { XCTAssertEqual(try sha(u), h, "navigation never modifies files") }
    }

    func testKeyboardNavigationInPhotoMode() async throws {
        let urls = [try makeAlphaPNG(name: "a.png"), try makeExifJPEG(name: "b.jpg"), try makeGIF(name: "c.gif")]
        let (wc, _) = try await open(urls)
        let names = wc.session.urls.map(\.lastPathComponent)
        func key(_ keyCode: UInt16) {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: wc.window!.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                     isARepeat: false, keyCode: keyCode)!
            wc.canvasView.keyDown(with: e)
        }
        key(124)   // →
        await waitUntil("→") { wc.imageDocument?.fileURL?.lastPathComponent == names[1] }
        key(119)   // End
        await waitUntil("End") { wc.imageDocument?.fileURL?.lastPathComponent == names[2] }
        key(115)   // Home
        await waitUntil("Home") { wc.imageDocument?.fileURL?.lastPathComponent == names[0] }
    }

    // MARK: - 8. Screenshots

    private func settings_browserStyle() -> ImageBrowserStyle { AppSettings.shared.photoBrowserStyle }

    func testScreenshots() async throws {
        // A readable scene: gradient sky, sun, hills.
        let ctx = rgbaContext(1600, 1000)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let grad = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.35, green: 0.6, blue: 0.95, alpha: 1),
                                                           CGColor(srgbRed: 0.95, green: 0.85, blue: 0.7, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1000), end: CGPoint(x: 0, y: 0), options: [])
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 1150, y: 650, width: 200, height: 200))
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: -300, y: -500, width: 1400, height: 900))
        ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.4, blue: 0.25, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 600, y: -600, width: 1500, height: 900))
        let scene = dir.appendingPathComponent("scene.png")
        try write(ctx.makeImage()!, type: .png, to: scene)

        let out = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("dpp-screens", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        print("DPP-SCREENSHOT-DIR \(out.path)")

        let (wc, doc) = try await open([scene, try makeAlphaPNG(name: "z.png")])
        _ = doc
        let window = try XCTUnwrap(wc.window)
        window.setContentSize(NSSize(width: 1280, height: 800))
        await waitUntil("scene preview") { self.isPreview(wc.canvasView.content) }

        func snap(_ name: String, appearance: NSAppearance.Name) throws {
            window.appearance = NSAppearance(named: appearance)
            window.contentView?.layoutSubtreeIfNeeded()
            for _ in 0..<40 { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02)) }   // let SwiftUI re-resolve semantic colours
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            for (suffix, view) in [("content", window.contentView), ("frame", window.contentView?.superview)] {
                guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return XCTFail("no bitmap rep") }
                view.cacheDisplay(in: view.bounds, to: rep)
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: out.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        try snap("photo-light", appearance: .aqua)
        try snap("photo-dark", appearance: .darkAqua)
        // Image browser (tiles) over the canvas.
        let oldStyle = settings_browserStyle()
        AppSettings.shared.photoBrowserStyle = .tiles
        wc.toggleImageBrowser(nil)
        await waitUntil("browser listed") { !wc.viewer.browser.items.isEmpty }
        try? await Task.sleep(for: .milliseconds(1200))   // thumbnails decode asynchronously
        try snap("browser-light", appearance: .aqua)
        wc.hideImageBrowser()
        AppSettings.shared.photoBrowserStyle = oldStyle

        await enterPaint(wc)
        let model = try XCTUnwrap(wc.canvas)
        window.setContentSize(NSSize(width: 1280, height: 800))
        wc.scrollView.zoomToFit(.window, allowUpscale: false)
        let t = ToolSettings.shared
        t.penWidth = 6
        t.primaryColor = NSColor(srgbRed: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        wc.activateTool(.pen)
        drag([CGPoint(x: 200, y: 700), CGPoint(x: 400, y: 600), CGPoint(x: 600, y: 760), CGPoint(x: 800, y: 620)], in: wc)
        t.primaryColor = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        t.shapeLineWidth = 5
        wc.activateTool(.shape)
        t.shapeKind = .ellipse
        drag([CGPoint(x: 300, y: 150), CGPoint(x: 700, y: 400)], in: wc)
        wc.activateTool(.text)
        click(CGPoint(x: 900, y: 300), in: wc, registersUndo: false)
        if let tool = wc.activeTool as? TextTool, let tv = tool.textView {
            beginEvent(for: tv)
            tv.insertText("Hello 日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
            beginEventCycle()
            tool.commit(force: true)
            endEventCycle()
        }
        wc.activateTool(.rectangleSelect)
        drag([CGPoint(x: 100, y: 100), CGPoint(x: 260, y: 230)], in: wc)
        XCTAssertTrue(model.undoManager?.canUndo ?? false)
        XCTAssertFalse(wc.inspectorItem.isCollapsed, "inspector is visible in Paint Mode")
        // Default: the tool palette is the horizontal ribbon above the canvas; the left pane stays collapsed.
        let settings = AppSettings.shared
        let oldPosition = settings.paintToolPalettePosition
        defer { settings.paintToolPalettePosition = oldPosition; wc.applyModeUI(animated: false) }
        settings.paintToolPalettePosition = .top
        wc.applyModeUI(animated: false)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertFalse(wc.ribbonHost.isHidden, "top tool ribbon is visible in Paint Mode")
        XCTAssertEqual(wc.ribbonHost.frame.height, ToolRibbonView.height, accuracy: 0.5)
        XCTAssertTrue(wc.paletteItem.isCollapsed, "left palette is collapsed while the ribbon is used")
        // Left position: the vertical palette pane comes back and the ribbon goes away.
        settings.paintToolPalettePosition = .left
        wc.applyModeUI(animated: false)
        XCTAssertTrue(wc.ribbonHost.isHidden)
        XCTAssertFalse(wc.paletteItem.isCollapsed)
        // NSSplitViewItem collapse animations do not progress without a live display; settle the final layout.
        wc.applyModeUI(animated: false)
        window.contentView?.layoutSubtreeIfNeeded()
        wc.splitViewController.splitView.adjustSubviews()
        window.contentView?.layoutSubtreeIfNeeded()
        await waitUntil("side panes laid out", timeout: 5) {
            window.contentView?.layoutSubtreeIfNeeded()
            return wc.paletteItem.viewController.view.frame.minX >= 0 && wc.paletteItem.viewController.view.frame.width > 40
        }
        let split = wc.splitViewController.splitView.bounds
        let pf = wc.paletteItem.viewController.view.frame, inf = wc.inspectorItem.viewController.view.frame
        XCTAssertGreaterThanOrEqual(pf.minX, 0, "tool palette is inside the window: \(pf)")
        XCTAssertGreaterThan(pf.width, 40)
        XCTAssertLessThanOrEqual(inf.maxX, split.maxX + 0.5, "inspector is inside the window: \(inf)")
        XCTAssertGreaterThan(inf.width, 200 - 5)
        try snap("paint-light", appearance: .aqua)
        try snap("paint-dark", appearance: .darkAqua)
        // Default layout: tool ribbon on top.
        AppSettings.shared.paintToolPalettePosition = .top
        wc.applyModeUI(animated: false)
        try snap("paint-ribbon-light", appearance: .aqua)
        try snap("paint-ribbon-dark", appearance: .darkAqua)
        window.appearance = nil
    }
}

