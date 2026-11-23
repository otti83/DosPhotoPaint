import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DosPhotoPaint

/// File-safety tests for the documents module: originals are never touched except by explicit
/// saves, saves are exact, failures keep the document intact, autosave never writes the original.
@MainActor
final class DocumentsTests: AppTestCase {
    private var dir: URL!
    private let png = UTType.png.identifier
    private let jpeg = UTType.jpeg.identifier

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Helpers

    private func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func solidImage(_ w: Int, _ h: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) -> CGImage {
        let buffer = RasterBuffer(width: w, height: h, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        buffer.fill(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255))
        return buffer.copyImage()!
    }

    private func writePNG(_ image: CGImage, name: String = "in.png") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try ImageEncoder.encode(image, as: .png).write(to: url)
        return url
    }

    private func open(_ url: URL, type: String? = nil) throws -> ImageDocument {
        try ImageDocument(for: url, withContentsOf: url, ofType: type ?? png)
    }

    private func save(_ doc: ImageDocument, to url: URL, type: String, _ op: NSDocument.SaveOperationType) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            doc.save(to: url, ofType: type, for: op) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }

    private func pixel(_ url: URL, _ x: Int = 0, _ y: Int = 0) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let image = try ImageLoader.loadFullImage(url: url).image
        return RasterBuffer(image: image)!.pixel(x: x, y: y)!
    }

    private func paint(_ doc: ImageDocument, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        doc.canvas!.activeLayer!.buffer.fill(CGColor(srgbRed: r, green: g, blue: b, alpha: 1), in: CGRect(x: 0, y: 0, width: 4, height: 4))
        doc.updateChangeCount(.changeDone)
    }

    // MARK: Original files stay untouched

    func testViewingMaterializingAndEditingNeverWritesOriginal() async throws {
        let url = try writePNG(solidImage(16, 16, r: 10, g: 20, b: 30))
        let before = try sha(url)
        let doc = try open(url)
        XCTAssertNotNil(doc.sourceInfo)
        try await doc.materializeCanvas()
        XCTAssertEqual(try sha(url), before, "materializing must not write")
        paint(doc, 1, 0, 0)
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertEqual(try sha(url), before, "editing without saving must not write")
    }

    func testSaveAsProjectFromUnmaterializedImageKeepsDocumentUsable() async throws {
        let url = try writePNG(solidImage(8, 6, r: 10, g: 20, b: 30))
        let doc = try open(url)
        XCTAssertFalse(doc.isMaterialized)
        let dpp = dir.appendingPathComponent("out.dpp")
        try await save(doc, to: dpp, type: ImageTypes.project.identifier, .saveAsOperation)
        XCTAssertTrue(doc.isMaterialized)
        XCTAssertEqual(doc.canvas?.layers.count, 1)
    }

    func testSaveUpdatesContent() async throws {
        let url = try writePNG(solidImage(16, 16, r: 10, g: 20, b: 30))
        let doc = try open(url)
        try await doc.materializeCanvas()
        paint(doc, 1, 0, 0)
        try await save(doc, to: url, type: png, .saveOperation)
        XCTAssertFalse(doc.isDocumentEdited)
        let p = try pixel(url, 1, 1)
        XCTAssertEqual([p.r, p.g, p.b, p.a], [255, 0, 0, 255])
        let q = try pixel(url, 10, 10)
        XCTAssertEqual([q.r, q.g, q.b], [10, 20, 30])
    }

    func testSaveAsLeavesOriginalUnchanged() async throws {
        let url = try writePNG(solidImage(16, 16, r: 10, g: 20, b: 30))
        let before = try sha(url)
        let doc = try open(url)
        try await doc.materializeCanvas()
        paint(doc, 0, 1, 0)
        let copy = dir.appendingPathComponent("copy.png")
        try await save(doc, to: copy, type: png, .saveAsOperation)
        XCTAssertEqual(try sha(url), before)
        let p = try pixel(copy, 1, 1)
        XCTAssertEqual([p.r, p.g, p.b], [0, 255, 0])
    }

    func testExportDoesNotChangeDocument() async throws {
        let url = try writePNG(solidImage(16, 16, r: 10, g: 20, b: 30))
        let doc = try open(url)
        try await doc.materializeCanvas()
        paint(doc, 0, 0, 1)
        let out = dir.appendingPathComponent("export.jpg")
        try await save(doc, to: out, type: jpeg, .saveToOperation)
        XCTAssertEqual(doc.fileURL, url)
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    // MARK: Formats

    func testPNGRoundTripKeepsAlpha() async throws {
        let doc = try ImageDocument(type: png)
        let layer = doc.canvas!.activeLayer!.buffer
        layer.clear()
        layer.fill(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), in: CGRect(x: 0, y: 0, width: 2, height: 2))
        layer.fill(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5), in: CGRect(x: 2, y: 0, width: 2, height: 2))
        let before = (0..<4).map { layer.pixel(x: $0, y: 0)! }
        let url = dir.appendingPathComponent("alpha.png")
        try await save(doc, to: url, type: png, .saveAsOperation)
        for x in 0..<4 {
            let p = try pixel(url, x, 0)
            XCTAssertEqual(p.a, before[x].a, "alpha at \(x)")
            XCTAssertEqual(p.r, before[x].r, "r at \(x)")
        }
        XCTAssertEqual(try pixel(url, 3, 3).a, 0)
    }

    func testJPEGSaveCompositesTransparencyOnMatte() async throws {
        let settings = AppSettings.shared
        let old = settings.saveJPEGBackground
        defer { settings.saveJPEGBackground = old }
        settings.saveJPEGBackground = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let doc = try ImageDocument(type: jpeg)
        doc.canvas!.activeLayer!.buffer.clear()
        let url = dir.appendingPathComponent("t.jpg")
        try await save(doc, to: url, type: jpeg, .saveAsOperation)
        let p = try pixel(url, 5, 5)
        XCTAssertLessThan(Int(p.r), 12)
        XCTAssertGreaterThan(Int(p.b), 240)
        XCTAssertEqual(p.a, 255)
    }

    func testEXIFOrientation6DecodesUprightAndSavesOrientation1() async throws {
        let url = dir.appendingPathComponent("rot.jpg")
        let image = solidImage(40, 20, r: 200, g: 50, b: 50)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, jpeg as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let doc = try open(url, type: jpeg)
        XCTAssertEqual(doc.pixelSize, CGSize(width: 20, height: 40))
        try await doc.materializeCanvas()
        XCTAssertEqual(doc.canvas?.size, CGSize(width: 20, height: 40))

        let out = dir.appendingPathComponent("out.jpg")
        try await save(doc, to: out, type: jpeg, .saveAsOperation)
        let src = CGImageSourceCreateWithURL(out as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 20)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 40)
        XCTAssertEqual((props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1, 1)
    }

    func testProjectRoundTripPreservesLayers() async throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func layer(_ name: String, _ r: CGFloat, visible: Bool, opacity: Double) -> Layer {
            let b = RasterBuffer(width: 8, height: 8, colorSpace: space)!
            b.fill(CGColor(srgbRed: r, green: 0.5, blue: 0, alpha: 1), in: CGRect(x: 0, y: 0, width: 4, height: 8))
            return Layer(name: name, buffer: b, isVisible: visible, opacity: opacity)
        }
        let layers = [layer("Bottom", 0.2, visible: true, opacity: 1), layer("Middle", 0.6, visible: false, opacity: 0.4), layer("Top", 1, visible: true, opacity: 0.75)]
        let model = CanvasModel(width: 8, height: 8, colorSpace: space, layers: layers, activeLayerID: layers[1].id)!
        let wrapper = try ProjectFormat.fileWrapper(for: model)
        let url = dir.appendingPathComponent("p.dpp")
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)

        let doc = try open(url, type: ImageTypes.project.identifier)
        let loaded = try XCTUnwrap(doc.canvas)
        XCTAssertEqual(loaded.layers.map(\.name), ["Bottom", "Middle", "Top"])
        XCTAssertEqual(loaded.layers.map(\.isVisible), [true, false, true])
        XCTAssertEqual(loaded.layers.map(\.opacity), [1, 0.4, 0.75])
        XCTAssertEqual(loaded.activeLayerID, layers[1].id)
        for (a, b) in zip(layers, loaded.layers) {
            XCTAssertEqual(a.buffer.pixel(x: 1, y: 1)!.r, b.buffer.pixel(x: 1, y: 1)!.r)
            XCTAssertEqual(a.buffer.pixel(x: 6, y: 1)!.a, b.buffer.pixel(x: 6, y: 1)!.a)
        }
    }

    // MARK: Write safety

    func testSaveToReadOnlyDirectoryFailsWithoutSideEffects() async throws {
        let doc = try ImageDocument(type: png)
        paint(doc, 1, 0, 0)
        let before = doc.canvas!.activeLayer!.buffer.pixel(x: 1, y: 1)!
        let ro = dir.appendingPathComponent("ro", isDirectory: true)
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ro.path)
        let target = ro.appendingPathComponent("x.png")
        do {
            try await save(doc, to: target, type: png, .saveAsOperation)
            XCTFail("saving into a read-only directory must fail")
        } catch {}
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertNil(doc.fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        let after = doc.canvas!.activeLayer!.buffer.pixel(x: 1, y: 1)!
        XCTAssertEqual([after.r, after.g, after.b, after.a], [before.r, before.g, before.b, before.a])
    }

    // MARK: Autosave & recovery

    func testAutosaveNeverWritesOriginalAndRecoveryRestoresLayers() async throws {
        let url = try writePNG(solidImage(16, 16, r: 10, g: 20, b: 30), name: "orig.jpg.png")
        let jpegURL = dir.appendingPathComponent("orig.jpg")
        try ImageEncoder.encode(try ImageLoader.loadFullImage(url: url).image, as: .jpeg).write(to: jpegURL)
        let before = try sha(jpegURL)

        let doc = try open(jpegURL, type: jpeg)
        try await doc.materializeCanvas()
        let canvas = doc.canvas!
        // Add a second layer so recovery has something to prove.
        let extra = Layer(name: "Extra", buffer: RasterBuffer(width: 16, height: 16, colorSpace: canvas.colorSpace)!)
        let two = CanvasModel(width: 16, height: 16, colorSpace: canvas.colorSpace,
                              layers: [canvas.layers[0], extra], activeLayerID: extra.id)!
        paint(doc, 1, 0, 0)
        // Stand-in autosave contents holding two layers (what a layered session would leave behind).
        let auto = dir.appendingPathComponent("autosave.dpp")
        try ProjectFormat.fileWrapper(for: two).write(to: auto, options: .atomic, originalContentsURL: nil)

        // Real autosave: must leave the original alone and use the project type.
        let autosaveError: Error? = await withCheckedContinuation { c in
            doc.autosave(withImplicitCancellability: false) { c.resume(returning: $0) }
        }
        XCTAssertNil(autosaveError)
        XCTAssertNotNil(doc.autosavedContentsFileURL)
        XCTAssertEqual(try sha(jpegURL), before, "autosave must never write the original")
        XCTAssertEqual(doc.fileURL, jpegURL)
        XCTAssertEqual(doc.autosavingFileType, ImageTypes.project.identifier)
        if let saved = doc.autosavedContentsFileURL { XCTAssertNotEqual(saved, jpegURL) }

        // Crash recovery.
        let recovered = try ImageDocument(for: jpegURL, withContentsOf: auto, ofType: jpeg)
        XCTAssertEqual(recovered.canvas?.layers.count, 2)
        XCTAssertEqual(recovered.canvas?.layers.last?.name, "Extra")
        XCTAssertEqual(recovered.fileURL, jpegURL)
        XCTAssertTrue(recovered.isDocumentEdited)
        XCTAssertEqual(try sha(jpegURL), before)
    }

    // MARK: Close confirmation setting

    private final class CloseProbe: NSObject {
        var result: Bool?
        @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) { result = shouldClose }
    }

    func testCloseWithoutConfirmationDiscardsWhenSettingOff() throws {
        let settings = AppSettings.shared
        let old = settings.confirmUnsavedOnClose
        defer { settings.confirmUnsavedOnClose = old }
        settings.confirmUnsavedOnClose = false
        let doc = try ImageDocument(type: png)
        doc.updateChangeCount(.changeDone)
        let probe = CloseProbe()
        doc.canClose(withDelegate: probe, shouldClose: #selector(CloseProbe.document(_:shouldClose:contextInfo:)), contextInfo: nil)
        XCTAssertEqual(probe.result, true)
    }

    // MARK: Review fixes

    /// AppKit may hand the autosave's own type (project) to `init(for:withContentsOf:ofType:)`;
    /// the document must still describe the original image file, or Save would write a package
    /// over the original image path.
    func testRecoveryOfImageKeepsImageTypeEvenIfAppKitPassesProjectType() async throws {
        let url = try writePNG(solidImage(16, 16, r: 10, g: 20, b: 30))
        let before = try sha(url)
        let canvas = CanvasModel(width: 16, height: 16, background: nil)!
        let auto = dir.appendingPathComponent("autosave.dpp")
        try ProjectFormat.fileWrapper(for: canvas).write(to: auto, options: .atomic, originalContentsURL: nil)
        let recovered = try ImageDocument(for: url, withContentsOf: auto, ofType: ImageTypes.project.identifier)
        XCTAssertEqual(recovered.fileURL, url)
        XCTAssertFalse(recovered.isProject, "document of a .png must not claim to be a project")
        XCTAssertEqual(UTType(recovered.fileType ?? "")?.conforms(to: .png), true)
        XCTAssertEqual(try sha(url), before)
    }

    func testSaveIsDisabledForUneditedFileDocument() throws {
        let url = try writePNG(solidImage(8, 8, r: 1, g: 2, b: 3))
        let doc = try open(url)
        let item = NSMenuItem(title: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        XCTAssertFalse(doc.validateUserInterfaceItem(item), "Save on an unedited photo would re-encode the original")
    }

    func testDuplicateOfUneditedImageStaysUsable() async throws {
        let url = try writePNG(solidImage(8, 8, r: 1, g: 2, b: 3))
        let before = try sha(url)
        let doc = try open(url)
        let copy = try doc.duplicate() as! ImageDocument
        XCTAssertNotNil(copy.canvas, "duplicate must carry its pixels")
        let model = try await copy.materializeCanvas()
        XCTAssertEqual(model.width, 8)
        XCTAssertEqual(try sha(url), before)
    }

    // MARK: Printing

    func testPrintViewFitsAndCentres() {
        let image = solidImage(200, 100, r: 0, g: 0, b: 0)
        let view = ImagePrintView(image: image, size: NSSize(width: 400, height: 400))
        XCTAssertEqual(view.imageRect, NSRect(x: 0, y: 100, width: 400, height: 200))
    }
}
