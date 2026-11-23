import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DosPhotoPaint

/// Polish fixes: robust multi-file open, off-main structural edits, font family names, Photo Mode
/// keys, shared documents across windows.
@MainActor
final class PolishTests: AppTestCase {
    private var dir: URL!
    private var undoManagers: [UndoManager] = []
    private var problems: [(String, String)] = []
    private var savedPresenter: ((String, String) -> Void)?
    private var savedThreshold = 0

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("polish-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savedPresenter = DocumentController.shared.problemPresenter
        savedThreshold = CanvasModel.offloadPixelThreshold
        problems = []
        DocumentController.shared.problemPresenter = { [unowned self] m, d in problems.append((m, d)) }
    }

    override func tearDownWithError() throws {
        CanvasModel.offloadPixelThreshold = savedThreshold
        if let savedPresenter { DocumentController.shared.problemPresenter = savedPresenter }
        TestHost.closeEverything()
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Helpers

    private func gradient(_ w: Int, _ h: Int, seed: Int = 0) -> CGImage {
        let b = RasterBuffer(width: w, height: h, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        b.withMutablePixels { p, bpr in
            for y in 0..<h { for x in 0..<w {
                let o = y * bpr + x * 4
                let a = UInt8(truncatingIfNeeded: 60 + (x * 5 + y * 3 + seed) % 196)
                p[o] = UInt8(truncatingIfNeeded: Int(a) * ((x * 7 + seed) % 256) / 255)
                p[o + 1] = UInt8(truncatingIfNeeded: Int(a) * ((y * 11) % 256) / 255)
                p[o + 2] = UInt8(truncatingIfNeeded: Int(a) * ((x + y) * 3 % 256) / 255)
                p[o + 3] = a
            } }
        }
        return b.copyImage()!
    }

    private func writePNG(_ name: String, _ w: Int = 40, _ h: Int = 30) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try ImageEncoder.encode(gradient(w, h), as: .png).write(to: url)
        return url
    }

    /// Three layers with distinct translucent content, opacities and one hidden layer.
    private func makeModel(_ w: Int = 48, _ h: Int = 36) -> CanvasModel {
        let c = CanvasModel(image: gradient(w, h))!
        let um = UndoManager()
        um.groupsByEvent = false
        undoManagers.append(um)
        c.undoManager = um
        for i in 1...2 {
            um.beginUndoGrouping(); c.addLayer(); um.endUndoGrouping()
            c.layers[i].buffer.replace(c.bounds, with: gradient(w, h, seed: i * 17))
            c.layers[i].opacity = i == 1 ? 0.6 : 0.35
        }
        return c
    }

    private func dump(_ c: CanvasModel) -> [[UInt8]] {
        c.layers.map { l in
            l.buffer.withMutablePixels { p, bpr in
                var out: [UInt8] = []
                for y in 0..<l.buffer.height { out += Array(UnsafeBufferPointer(start: p + y * bpr, count: l.buffer.width * 4)) }
                return out
            } ?? []
        }
    }

    private func grouped(_ c: CanvasModel, _ body: () async throws -> Void) async rethrows {
        c.undoManager?.beginUndoGrouping()
        defer { c.undoManager?.endUndoGrouping() }
        try await body()
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 30, _ condition: () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "Timed out waiting for: \(what)")
    }

    private func open(_ urls: [URL]) async -> [URL: NSDocument] {
        await withCheckedContinuation { (c: CheckedContinuation<[URL: NSDocument], Never>) in
            DocumentController.shared.openForViewing(urls) { c.resume(returning: $0) }
        }
    }

    private func windowController(_ doc: NSDocument?) -> MainWindowController? {
        doc?.windowControllers.compactMap { $0 as? MainWindowController }.first
    }

    // MARK: 1. Multi-file open

    func testMultiFileOpenSkipsUnreadableFirstFile() async throws {
        let bad = dir.appendingPathComponent("a_corrupt.png")
        try Data("this is not a png".utf8).write(to: bad)
        let good1 = try writePNG("b.png"), good2 = try writePNG("c.png")
        let results = await open([good2, bad, good1])
        XCTAssertEqual(results.count, 1)
        let doc = try XCTUnwrap(results.values.first as? ImageDocument)
        XCTAssertEqual(doc.fileURL?.lastPathComponent, "b.png", "first readable file in session order opens")
        let wc = try XCTUnwrap(windowController(doc))
        XCTAssertEqual(wc.session.urls.map(\.lastPathComponent), ["b.png", "c.png"], "unreadable file is dropped from the session")
        XCTAssertEqual(problems.count, 1, "reported once")
        XCTAssertTrue(problems[0].1.contains("a_corrupt.png"))
        XCTAssertFalse(problems[0].1.contains("b.png"))
    }

    func testMultiFileOpenAllUnreadableReportsOnce() async throws {
        let urls = try ["a.png", "b.png"].map { name -> URL in
            let u = dir.appendingPathComponent(name)
            try Data("garbage".utf8).write(to: u)
            return u
        }
        let results = await open(urls)
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].1.contains("a.png") && problems[0].1.contains("b.png"))
        XCTAssertTrue(DocumentController.shared.documents.isEmpty)
    }

    // MARK: 2. Off-main structural edits are identical to the synchronous path

    func testMergeDownOffloadedMatchesSynchronous() async throws {
        let sync = makeModel(), off = makeModel()
        let original = dump(off)
        XCTAssertEqual(dump(sync), original)
        sync.undoManager?.beginUndoGrouping(); XCTAssertTrue(sync.mergeActiveLayerDown()); sync.undoManager?.endUndoGrouping()
        var ok = false
        await grouped(off) { ok = await off.mergeActiveLayerDownOffloaded() }
        XCTAssertTrue(ok)
        XCTAssertEqual(dump(off), dump(sync), "identical pixels")
        XCTAssertEqual(off.layers.count, 2)
        XCTAssertEqual(off.activeLayerID, off.layers[1].id)
        off.undoManager?.undo()
        XCTAssertEqual(dump(off), original, "undo is exact")
        XCTAssertEqual(off.layers.map(\.opacity), [1, 0.6, 0.35])
    }

    func testFlattenOffloadedMatchesSynchronousIncludingHiddenLayer() async throws {
        let sync = makeModel(), off = makeModel()
        for m in [sync, off] { m.layers[1].isVisible = false }
        let original = dump(off)
        sync.undoManager?.beginUndoGrouping(); XCTAssertTrue(sync.flatten()); sync.undoManager?.endUndoGrouping()
        var ok = false
        await grouped(off) { ok = await off.flattenOffloaded() }
        XCTAssertTrue(ok)
        XCTAssertEqual(off.layers.count, 1)
        XCTAssertEqual(dump(off), dump(sync))
        XCTAssertTrue(off.layers[0].isVisible)
        XCTAssertEqual(off.layers[0].opacity, 1)
        off.undoManager?.undo()
        XCTAssertEqual(dump(off), original)
        XCTAssertEqual(off.layers.count, 3)
        XCTAssertFalse(off.layers[1].isVisible)
    }

    func testCropOffloadedMatchesSynchronous() async throws {
        let sync = makeModel(), off = makeModel()
        for m in [sync, off] { m.setSelection(.rect(CGRect(x: 5, y: 4, width: 20, height: 10)), undoable: false) }
        let original = dump(off)
        let rect = CGRect(x: 5, y: 4, width: 20, height: 10)
        sync.undoManager?.beginUndoGrouping(); XCTAssertTrue(sync.crop(to: rect)); sync.undoManager?.endUndoGrouping()
        var ok = false
        await grouped(off) { ok = await off.cropOffloaded(to: rect) }
        XCTAssertTrue(ok)
        XCTAssertEqual(off.size, sync.size)
        XCTAssertEqual(dump(off), dump(sync))
        XCTAssertNil(off.selection)
        off.undoManager?.undo()
        XCTAssertEqual(off.size, CGSize(width: 48, height: 36))
        XCTAssertEqual(dump(off), original)
        XCTAssertNotNil(off.selection, "undo restores the selection")
    }

    func testOffloadedEditIsDiscardedWhenCanvasChangesMeanwhile() async throws {
        let c = makeModel()
        let original = dump(c)
        let task = Task { await c.flattenOffloaded() }
        await Task.yield()   // the edit has copied its inputs and is waiting for the background work
        c.layers[0].contentRevision &+= 1   // a stroke landed meanwhile
        let ok = await task.value
        XCTAssertFalse(ok)
        XCTAssertEqual(c.layers.count, 3)
        XCTAssertEqual(dump(c), original)
    }

    func testControllerRunsLargeEditsOffMainWithBusyStateAndBlocksReentrancy() async throws {
        let url = try writePNG("big.png", 64, 48)
        let results = await open([url])
        let wc = try XCTUnwrap(windowController(results.values.first))
        await wc.enterPaintMode()
        let model = try XCTUnwrap(wc.canvas)
        let doc = try XCTUnwrap(wc.imageDocument)
        let um = try XCTUnwrap(doc.undoManager)
        um.groupsByEvent = false
        um.beginUndoGrouping(); model.addLayer(); um.endUndoGrouping()
        model.layers[1].buffer.replace(model.bounds, with: gradient(64, 48, seed: 9))
        let reference = CanvasModel(image: gradient(64, 48))!
        reference.addLayer()
        reference.layers[1].buffer.replace(reference.bounds, with: gradient(64, 48, seed: 9))
        reference.flatten()

        CanvasModel.offloadPixelThreshold = 0
        um.beginUndoGrouping()
        wc.flattenImage(nil)
        XCTAssertTrue(wc.state.isLoading, "busy as soon as the edit starts")
        XCTAssertFalse(wc.isEnabled(#selector(AppActions.flattenImage(_:)), tag: 0), "no re-entrancy from the menu")
        wc.flattenImage(nil)   // ignored
        await waitUntil("flatten finished") { !wc.state.isLoading }
        um.endUndoGrouping()
        XCTAssertEqual(model.layers.count, 1)
        XCTAssertEqual(dump(model), dump(reference))
        XCTAssertNil(wc.state.statusMessage)
        um.undo()
        XCTAssertEqual(model.layers.count, 2)
    }

    // MARK: 3. Font families

    func testFontFamilyEntriesNameTheSystemFont() {
        let entries = FontFamilies.entries()
        XCTAssertEqual(entries.first?.family, FontFamilies.systemFamily)
        XCTAssertEqual(entries.first?.displayName, FontFamilies.systemDisplayName)
        XCTAssertFalse(FontFamilies.systemDisplayName.hasPrefix("."))
        XCTAssertGreaterThan(entries.count, 5)
        for e in entries {
            XCTAssertFalse(e.displayName.isEmpty)
            XCTAssertFalse(e.displayName.hasPrefix("."), "private family leaked: \(e.family)")
        }
        XCTAssertEqual(Set(entries.map(\.family)).count, entries.count, "unique families")
        let system = NSFont.systemFont(ofSize: 12)
        XCTAssertEqual(FontFamilies.family(forFontName: system.fontName), FontFamilies.systemFamily)
        XCTAssertEqual(FontFamilies.fontName(forFamily: FontFamilies.systemFamily), system.fontName)
        let helvetica = FontFamilies.fontName(forFamily: "Helvetica")
        XCTAssertNotNil(helvetica)
        XCTAssertEqual(FontFamilies.family(forFontName: helvetica ?? ""), "Helvetica")
    }

    // MARK: 4. Photo Mode keys

    private func key(_ code: UInt16, chars: String, in wc: MainWindowController) -> Bool {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: wc.window!.windowNumber, context: nil, characters: chars,
                                 charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        return wc.canvasView(wc.canvasView, keyDown: e)
    }

    func testPhotoModeSpaceAndEscapeAreSilentNoOpsWithoutSlideshow() async throws {
        let results = await open([try writePNG("a.png"), try writePNG("b.png")])
        let wc = try XCTUnwrap(windowController(results.values.first))
        XCTAssertEqual(wc.state.mode, .photo)
        XCTAssertFalse(wc.state.isSlideshowRunning)
        XCTAssertTrue(key(49, chars: " ", in: wc), "Space is consumed (falling through would beep)")
        XCTAssertTrue(key(53, chars: "\u{1b}", in: wc), "Escape is consumed")
        XCTAssertTrue(key(123, chars: "\u{F702}", in: wc))
        XCTAssertFalse(key(0, chars: "a", in: wc), "other keys keep the standard responder behaviour")
    }

    // MARK: 7. One document in two windows

    func testClosingOneOfTwoWindowsOfADocumentKeepsItAndPromptsOnlyForTheLast() async throws {
        let a = try writePNG("a.png"), b = try writePNG("b.png")
        let openedA = await open([a])
        let docA = try XCTUnwrap(openedA.values.first as? ImageDocument)
        let wc1 = try XCTUnwrap(windowController(docA))
        let openedB = await open([b])
        let docB = try XCTUnwrap(openedB.values.first as? ImageDocument)
        let wc2 = try XCTUnwrap(windowController(docB))
        XCTAssertFalse(wc1 === wc2)

        await wc2.navigate(to: a)
        XCTAssertTrue(wc2.imageDocument === docA)
        XCTAssertEqual(docA.windowControllers.count, 2)
        XCTAssertFalse(DocumentController.shared.documents.contains(docB), "clean document left behind is closed")

        // Edit the shared document.
        _ = try await docA.materializeCanvas()
        docA.updateChangeCount(.changeDone)
        XCTAssertTrue(docA.isDocumentEdited)

        // Navigating one window away neither prompts nor closes the document under the other window.
        await wc2.navigate(to: b)
        XCTAssertEqual(docA.windowControllers.count, 1)
        XCTAssertTrue(docA.windowControllers.first === wc1)
        XCTAssertTrue(DocumentController.shared.documents.contains(docA))
        XCTAssertTrue(docA.isDocumentEdited, "edits stay")
        XCTAssertNil(wc1.window?.attachedSheet)
        XCTAssertNil(wc2.window?.attachedSheet, "no unsaved-changes prompt while another window shows the document")

        // Two windows again; closing one removes only that controller.
        await wc2.navigate(to: a)
        XCTAssertEqual(docA.windowControllers.count, 2)
        wc2.window?.makeKeyAndOrderFront(nil)
        wc2.window?.performClose(nil)   // what the close button does: no prompt, the other window still shows the edits
        XCTAssertNil(wc2.window?.attachedSheet, "no prompt while another window shows the document")
        XCTAssertEqual(docA.windowControllers.count, 1)
        XCTAssertTrue(DocumentController.shared.documents.contains(docA), "document survives closing one of two windows")
        XCTAssertTrue(docA.isDocumentEdited)

        // The last window asks about the unsaved changes.
        wc1.window?.makeKeyAndOrderFront(nil)
        wc1.window?.performClose(nil)
        await waitUntil("unsaved-changes sheet for the last window", timeout: 5) { wc1.window?.attachedSheet != nil }
        if let sheet = wc1.window?.attachedSheet { wc1.window?.endSheet(sheet) }
        docA.updateChangeCount(.changeCleared)
    }
}
