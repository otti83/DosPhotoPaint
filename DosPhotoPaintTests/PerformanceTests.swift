import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DosPhotoPaint

/// Performance measurements. Every number is printed as `PERF <name>: <value>` so a run can be
/// grepped (`grep PERF`). Conditions: machine = `sysctl hw.model`, build configuration noted in
/// each header line (Debug unless the test bundle is built Release), synthetic JPEGs (see
/// `makeJPEG`), unit-test host process (activation policy .prohibited, no on-screen drawing).
/// See docs/PERFORMANCE.md.
@MainActor
final class PerformanceTests: AppTestCase {
    // MARK: - Helpers

    private static let dir: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("DPPPerf-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static var jpegCache: [String: URL] = [:]

    private static var configuration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    private static var hwModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    private func perf(_ name: String, _ value: String) { print("PERF \(name): \(value)") }
    private func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    private func time(_ body: () throws -> Void) rethrows -> Double {
        let c = ContinuousClock()
        let start = c.now
        try body()
        return ms(c.now - start)
    }

    /// Resident footprint in bytes (what Activity Monitor calls "Memory").
    private func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
    private func mb(_ bytes: Int) -> Double { Double(bytes) / 1_048_576 }

    /// Writes (once per size) a JPEG with photo-like detail: smooth gradients plus blocky noise
    /// so the entropy-coded size is realistic (≈ 1–3 bytes/pixel at quality 0.85, not a flat colour).
    private func makeJPEG(width: Int, height: Int, name: String? = nil) throws -> URL {
        let key = name ?? "\(width)x\(height)"
        if let url = Self.jpegCache[key] { return url }
        let buffer = try XCTUnwrap(RasterBuffer(width: width, height: height, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!))
        buffer.withMutablePixels { p, bpr in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for y in 0..<height {
                let row = p + y * bpr
                for x in 0..<width {
                    if x & 3 == 0 { seed = seed &* 6364136223846793005 &+ 1442695040888963407 }
                    let n = Int(seed >> 59)  // 0..31
                    let r = (x * 255 / width + n) & 255
                    let g = (y * 255 / height + n / 2) & 255
                    let b = ((x + y) * 255 / (width + height) + n) & 255
                    row[x * 4] = UInt8(r); row[x * 4 + 1] = UInt8(g); row[x * 4 + 2] = UInt8(b); row[x * 4 + 3] = 255
                }
            }
        }
        let image = try XCTUnwrap(buffer.copyImage())
        let url = Self.dir.appendingPathComponent("\(key).jpg")
        try ImageEncoder.encode(image, as: .jpeg).write(to: url)
        Self.jpegCache[key] = url
        return url
    }

    /// N distinct files (copies) so cache keys differ.
    private func makeJPEGSet(count: Int, width: Int, height: Int) throws -> [URL] {
        let src = try makeJPEG(width: width, height: height)
        return try (0..<count).map { i in
            let url = Self.dir.appendingPathComponent("set-\(width)x\(height)-\(i).jpg")
            if !FileManager.default.fileExists(atPath: url.path) { try FileManager.default.copyItem(at: src, to: url) }
            return url
        }
    }

    private func header(_ title: String) {
        perf("\(title) [conditions]", "\(Self.hwModel), \(Self.configuration), \(ProcessInfo.processInfo.physicalMemory >> 30) GB RAM")
    }

    /// Display budget used by a window on a 2560×1600 @2x screen (longest edge 5120 px).
    private let budget = 5120

    // MARK: - Launch

    func testLaunchTimeMainToDidFinishLaunching() throws {
        #if DEBUG
        header("launch")
        let t = try XCTUnwrap(LaunchTiming.mainToDidFinishLaunching, "stamps not recorded")
        perf("launch main()->applicationDidFinishLaunching (ms)", fmt(t * 1000))
        XCTAssertLessThan(t, 2.0)
        #else
        throw XCTSkip("LaunchTiming is compiled out of Release builds")
        #endif
    }

    // MARK: - Cold path

    func testColdOpenFor24MPJPEGToPreviewDisplayed() async throws {
        header("cold-open 24MP (6000x4000)")
        let url = try makeJPEG(width: 6000, height: 4000)
        var samples: [Double] = []
        for i in 0..<3 {
            ImageCache.shared.removeAll()
            let controller = DocumentController.shared
            let clock = ContinuousClock()
            let start = clock.now
            controller.openForViewing([url])
            var shown: Duration?
            var docFound: ImageDocument?
            var cacheSeen = false
            let deadline = clock.now + .seconds(20)
            while clock.now < deadline {
                if !cacheSeen, ImageCache.shared.cachedImage(for: url, maxPixelSize: MainWindowController.displayPixelBudget(for: nil)) != nil {
                    cacheSeen = true
                    perf("cold-open run \(i + 1)   sharp decode in cache (ms)", fmt(ms(clock.now - start)))
                }
                if docFound == nil, let d = controller.document(for: url) as? ImageDocument {
                    docFound = d
                    perf("cold-open run \(i + 1)   document registered (ms)", fmt(ms(clock.now - start)))
                }
                if let wc = docFound?.windowControllers.first as? MainWindowController,
                   case .preview = wc.canvasView.content { shown = clock.now - start; break }
                try await Task.sleep(for: .milliseconds(1))
            }
            let doc = try XCTUnwrap(docFound, "document never opened")
            let elapsed = try XCTUnwrap(shown, "preview never displayed")
            samples.append(ms(elapsed))
            perf("cold-open run \(i + 1) openForViewing->preview (ms)", fmt(ms(elapsed)))
            doc.close()
            try await Task.sleep(for: .milliseconds(50))
        }
        perf("cold-open median (ms)", fmt(samples.sorted()[1]))
    }

    /// Pieces of the cold path that run on the main thread before/around the decode.
    func testColdPathMainThreadPieces() throws {
        header("cold-path pieces, 24MP")
        let url = try makeJPEG(width: 6000, height: 4000)
        _ = try ImageLoader.info(for: url)  // warm file cache
        perf("ImageLoader.info header read (ms)", stats(try (0..<5).map { _ in try time { _ = try ImageLoader.info(for: url) } }))
        var wcSamples: [Double] = []
        for _ in 0..<3 {
            var wc: MainWindowController?
            wcSamples.append(time { wc = MainWindowController(initialMode: .photo, sessionURLs: nil) })
            wc?.close()
        }
        perf("MainWindowController.init (ms)", stats(wcSamples))
    }

    func testDisplayDecodeCostBySizeOn24MP() throws {
        header("decode by max pixel size, 24MP source")
        let url = try makeJPEG(width: 6000, height: 4000)
        for size in [1024, 2048, 2560, 3000, 5120] {
            var samples: [Double] = []
            for _ in 0..<3 { samples.append(try time { _ = try ImageLoader.loadDisplayImage(url: url, maxPixelSize: size) }) }
            perf("24MP loadDisplayImage maxPixelSize \(size) (ms)", stats(samples))
        }
    }

    /// Photo Mode draw of a decoded preview into a 1400x900 viewport.
    func testPreviewDrawCost() throws {
        header("preview draw 5120x3413 into 1400x900 viewport")
        let url = try makeJPEG(width: 6000, height: 4000)
        let image = try ImageLoader.loadDisplayImage(url: url, maxPixelSize: 5120)
        let scroll = CanvasScrollView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        let view = CanvasView(frame: .zero)
        scroll.documentView = view
        view.content = .preview(image, pixelSize: CGSize(width: 6000, height: 4000))
        let zoom: CGFloat = 1400.0 / 6000.0
        scroll.magnification = zoom
        for checker in [true, false] {
            view.showsCheckerboard = checker
            var samples: [Double] = []
            for _ in 0..<5 { samples.append(time { drawOffscreen(view, rect: CGRect(x: 0, y: 0, width: 6000, height: 4000), zoom: zoom) }) }
            perf("preview full draw checkerboard=\(checker) (ms)", stats(samples))
        }
    }

    // MARK: - ImageCache

    func testImageCacheDecodeVsCachedHit() async throws {
        header("cache decode vs hit")
        for (w, h, label) in [(4000, 3000, "12MP"), (6000, 4000, "24MP")] {
            let url = try makeJPEG(width: w, height: h)
            ImageCache.shared.removeAll()
            let c = ContinuousClock()
            var s = c.now
            _ = try await ImageCache.shared.displayImage(for: url, maxPixelSize: budget)
            let uncached = ms(c.now - s)
            s = c.now
            _ = try await ImageCache.shared.displayImage(for: url, maxPixelSize: budget)
            let hit = ms(c.now - s)
            perf("\(label) display decode uncached (ms)", fmt(uncached))
            perf("\(label) display decode cached hit (ms)", fmt(hit))
            XCTAssertLessThan(hit, uncached)
        }
    }

    func testSteppingTwentyImagesCachedVsUncached() async throws {
        header("step 20x12MP, budget \(budget)")
        let urls = try makeJPEGSet(count: 20, width: 4000, height: 3000)
        // Uncached: every step is a cold decode.
        ImageCache.shared.removeAll()
        var uncached: [Double] = []
        for url in urls {
            let c = ContinuousClock(); let s = c.now
            _ = try await ImageCache.shared.displayImage(for: url, maxPixelSize: budget)
            uncached.append(ms(c.now - s))
            ImageCache.shared.removeAll()
        }
        // Preloaded: like the viewer, prefetch the next 2 on arrival, dwell 400 ms, then step.
        ImageCache.shared.removeAll()
        var cached: [Double] = []
        _ = try await ImageCache.shared.displayImage(for: urls[0], maxPixelSize: budget)
        for i in 1..<urls.count {
            for u in ImagePreloader.neighbours(of: i - 1, in: urls, count: 2, loop: false) {
                ImageCache.shared.prefetch(u, maxPixelSize: budget)
            }
            try await Task.sleep(for: .milliseconds(400))
            let c = ContinuousClock(); let s = c.now
            _ = try await ImageCache.shared.displayImage(for: urls[i], maxPixelSize: budget)
            cached.append(ms(c.now - s))
        }
        let avg = { (a: [Double]) in a.reduce(0, +) / Double(a.count) }
        perf("step uncached avg (ms)", fmt(avg(uncached)))
        perf("step with preload avg (ms)", fmt(avg(cached)))
        perf("step with preload max (ms)", fmt(cached.max() ?? 0))
        XCTAssertLessThan(avg(cached), avg(uncached))
    }

    // MARK: - Memory

    func testMemoryPlateauWhileSteppingThirtyImages() async throws {
        header("memory step 30x12MP, budget \(budget), cache \(AppSettings.shared.performanceCacheMB) MB")
        let urls = try makeJPEGSet(count: 30, width: 4000, height: 3000)
        ImageCache.shared.removeAll()
        let base = footprint()
        var peak = base
        var series: [Int] = []
        for (i, url) in urls.enumerated() {
            for u in ImagePreloader.neighbours(of: i, in: urls, count: 2, loop: false) {
                ImageCache.shared.prefetch(u, maxPixelSize: budget)
            }
            _ = try await ImageCache.shared.displayImage(for: url, maxPixelSize: budget)
            try await Task.sleep(for: .milliseconds(150))
            let f = footprint()
            series.append(f)
            peak = max(peak, f)
        }
        perf("footprint before (MB)", fmt(mb(base)))
        perf("footprint peak (MB)", fmt(mb(peak)))
        perf("footprint after step 15 / 30 (MB)", "\(fmt(mb(series[14]))) / \(fmt(mb(series[29])))")
        let peakFirstHalf = series[..<15].max() ?? 0
        let peakSecondHalf = series[15...].max() ?? 0
        perf("peak 1st half / 2nd half (MB)", "\(fmt(mb(peakFirstHalf))) / \(fmt(mb(peakSecondHalf)))")
        // Plateau: the second half must not exceed the first by more than a few decoded images.
        XCTAssertLessThan(mb(peakSecondHalf) - mb(peakFirstHalf), 300)
        ImageCache.shared.removeAll()
    }

    func testMemoryAfterMaterializing6000x4000Canvas() throws {
        header("memory 6000x4000 canvas")
        let before = footprint()
        let model = try XCTUnwrap(CanvasModel(width: 6000, height: 4000, background: CGColor(gray: 1, alpha: 1)))
        model.updateComposite()
        let after = footprint()
        perf("6000x4000 canvas footprint delta (MB)", fmt(mb(after - before)))
        perf("6000x4000 canvas estimatedMemoryBytes (MB)", fmt(mb(model.estimatedMemoryBytes)))
        XCTAssertLessThan(mb(after - before), 600)
    }

    // MARK: - Brush

    private struct BrushRig {
        let model: CanvasModel
        let view: CanvasView
        let scroll: CanvasScrollView
        let context: ToolContext
        let undo: UndoManager
        var dirty: CGRect = .null
    }

    private func makeRig(width: Int, height: Int, zoom: CGFloat) throws -> BrushRig {
        let model = try XCTUnwrap(CanvasModel(width: width, height: height, background: CGColor(gray: 1, alpha: 1)))
        let undo = UndoManager()
        undo.levelsOfUndo = 50
        model.undoManager = undo
        let scroll = CanvasScrollView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        let view = CanvasView(frame: .zero)
        scroll.documentView = view
        view.content = .canvas(model)
        scroll.magnification = zoom
        let suite = "perf.\(UUID().uuidString)"
        let settings = ToolSettings(defaults: UserDefaults(suiteName: suite)!)
        UserDefaults.standard.removePersistentDomain(forName: suite)
        settings.primaryColor = NSColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        settings.opacity = 1
        let ctx = ToolContext(canvas: model, settings: settings, view: view, windowState: WindowState())
        return BrushRig(model: model, view: view, scroll: scroll, context: ctx, undo: undo)
    }

    /// Draws `rect` (image pixels) of the view into an offscreen bitmap at the current zoom.
    private func drawOffscreen(_ view: CanvasView, rect: CGRect, zoom: CGFloat) {
        let w = max(1, Int(ceil(rect.width * zoom))), h = max(1, Int(ceil(rect.height * zoom)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        view.draw(rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func toolEvent(_ p: CGPoint) -> ToolEvent {
        ToolEvent(location: p, pressure: 1, modifiers: [], clickCount: 1, isTablet: false)
    }

    /// Runs one stroke of `segments` drag events; returns per-segment (tool, composite+draw) ms.
    private func runStroke(_ rig: inout BrushRig, tool: StrokeTool, zoom: CGFloat, segments: Int,
                           origin: CGPoint, step: CGFloat) -> (tool: [Double], present: [Double]) {
        var toolMs: [Double] = [], presentMs: [Double] = []
        var pending = CGRect.null
        let previous = rig.model.onInvalidate
        rig.model.onInvalidate = { r in pending = pending.union(r); previous?(r) }
        tool.mouseDown(toolEvent(origin), context: rig.context)
        for i in 1...segments {
            let p = CGPoint(x: origin.x + CGFloat(i) * step, y: origin.y + 120 * sin(CGFloat(i) / 9))
            pending = .null
            toolMs.append(time { tool.mouseDragged(toolEvent(p), context: rig.context) })
            let region = pending.insetBy(dx: -2, dy: -2).intersection(rig.model.bounds)
            presentMs.append(time {
                rig.model.updateComposite()
                drawOffscreen(rig.view, rect: region, zoom: zoom)
            })
        }
        tool.mouseUp(toolEvent(origin), context: rig.context)
        rig.model.onInvalidate = previous
        return (toolMs, presentMs)
    }

    private func stats(_ a: [Double]) -> String {
        let s = a.sorted()
        return "avg \(fmt(a.reduce(0, +) / Double(a.count))) / p95 \(fmt(s[Int(Double(s.count - 1) * 0.95)])) / max \(fmt(s.last ?? 0))"
    }

    func testBrushSegmentCostOn4000x3000() throws {
        header("brush 4000x3000, 48 segments of 24 px")
        for zoom in [1.0, 0.25] {
            for (label, type, size) in [("hard round 20px", BrushType.hard, 20.0), ("soft 40px", BrushType.soft, 40.0)] {
                var rig = try makeRig(width: 4000, height: 3000, zoom: zoom)
                rig.context.settings.brushType = type
                rig.context.settings.brushSize = size
                rig.context.settings.brushHardness = 0.5
                let tool = StrokeTool(kind: .brush)
                rig.model.updateComposite()
                let r = runStroke(&rig, tool: tool, zoom: zoom, segments: 48, origin: CGPoint(x: 800, y: 1200), step: 24)
                perf("segment tool zoom \(zoom) \(label) (ms)", stats(r.tool))
                perf("segment composite+draw zoom \(zoom) \(label) (ms)", stats(r.present))
                let total = zip(r.tool, r.present).map { $0 + $1 }
                perf("segment TOTAL zoom \(zoom) \(label) (ms)", stats(total))
                XCTAssertLessThan(total.reduce(0, +) / Double(total.count), 16.7 * (Self.configuration == "Debug" ? 4 : 1))
            }
        }
    }

    func testFullCanvasRecomposite4000x3000() throws {
        header("full recomposite 4000x3000, 1 layer")
        let rig = try makeRig(width: 4000, height: 3000, zoom: 1)
        var samples: [Double] = []
        for _ in 0..<5 {
            rig.model.invalidateAll()
            samples.append(time { rig.model.updateComposite() })
        }
        perf("full recomposite 1 layer (ms)", stats(samples))
        // Two layers + one preview stroke forces the transparency-layer path.
        XCTAssertTrue(rig.model.addLayer())
        samples = []
        for _ in 0..<5 {
            rig.model.invalidateAll()
            samples.append(time { rig.model.updateComposite() })
        }
        perf("full recomposite 2 layers (ms)", stats(samples))
        var drawSamples: [Double] = []
        for _ in 0..<3 {
            drawSamples.append(time { drawOffscreen(rig.view, rect: CGRect(x: 0, y: 0, width: 1400, height: 900), zoom: 1) })
        }
        perf("draw 1400x900 viewport @zoom 1 (ms)", stats(drawSamples))
        rig.view.showsCheckerboard = false
        drawSamples = []
        for _ in 0..<3 {
            drawSamples.append(time { drawOffscreen(rig.view, rect: CGRect(x: 0, y: 0, width: 1400, height: 900), zoom: 1) })
        }
        perf("draw 1400x900 viewport @zoom 1, no checkerboard (ms)", stats(drawSamples))
    }

    // MARK: - Undo memory

    func testUndoMemoryFiftyStrokes4000x3000() throws {
        header("undo 50 strokes 4000x3000, stroke ≈ 1200x240 px bbox, brush 20 px")
        var rig = try makeRig(width: 4000, height: 3000, zoom: 1)
        let tool = StrokeTool(kind: .brush)
        rig.context.settings.brushType = .hard
        rig.context.settings.brushSize = 20
        let before = footprint()
        for i in 0..<50 {
            _ = runStroke(&rig, tool: tool, zoom: 1, segments: 50, origin: CGPoint(x: 400 + CGFloat(i % 5) * 50, y: 300 + CGFloat(i) * 50), step: 24)
        }
        let retained = rig.model.regionUndoBytesRegistered
        let naive = 50 * rig.model.layers[0].buffer.byteCount
        perf("region undo retained, 50 strokes (MB)", fmt(mb(retained)))
        perf("naive full-layer snapshots, 50 strokes (MB)", fmt(mb(naive)))
        perf("ratio region/naive", fmt(Double(retained) / Double(naive)))
        perf("footprint delta over 50 strokes (MB)", fmt(mb(footprint() - before)))
        XCTAssertLessThan(retained, naive / 10)
        XCTAssertEqual(rig.undo.canUndo, true)
    }

    /// Long diagonal strokes: the worst case for bounding-box undo (bbox ≈ whole canvas).
    func testUndoMemoryFiftyDiagonalStrokes4000x3000() throws {
        header("undo 50 diagonal strokes 4000x3000 (bbox ≈ canvas), brush 20 px")
        var rig = try makeRig(width: 4000, height: 3000, zoom: 1)
        let tool = StrokeTool(kind: .brush)
        rig.context.settings.brushType = .hard
        rig.context.settings.brushSize = 20
        for i in 0..<50 {
            let y0 = 40 + CGFloat(i)
            tool.mouseDown(toolEvent(CGPoint(x: 20, y: y0)), context: rig.context)
            for k in 1...40 {
                tool.mouseDragged(toolEvent(CGPoint(x: 20 + CGFloat(k) * 98, y: y0 + CGFloat(k) * 70)), context: rig.context)
            }
            tool.mouseUp(toolEvent(.zero), context: rig.context)
        }
        let retained = rig.model.regionUndoBytesRegistered
        let naive = 50 * rig.model.layers[0].buffer.byteCount
        perf("diagonal: region undo retained (MB)", fmt(mb(retained)))
        perf("diagonal: naive full-layer snapshots (MB)", fmt(mb(naive)))
        perf("diagonal: ratio", fmt(Double(retained) / Double(naive)))
        XCTAssertLessThan(retained, naive / 5)
    }

    func testTiledStrokeUndoRedoRestoresPixelsExactly() throws {
        let rig = try makeRig(width: 1200, height: 900, zoom: 1)
        let tool = StrokeTool(kind: .brush)
        rig.context.settings.brushType = .hard
        rig.context.settings.brushSize = 14
        let before = try XCTUnwrap(rig.model.layers[0].buffer.copyImage())
        tool.mouseDown(toolEvent(CGPoint(x: 10, y: 10)), context: rig.context)
        for k in 1...30 { tool.mouseDragged(toolEvent(CGPoint(x: 10 + CGFloat(k) * 36, y: 10 + CGFloat(k) * 28)), context: rig.context) }
        tool.mouseUp(toolEvent(.zero), context: rig.context)
        let painted = try XCTUnwrap(rig.model.layers[0].buffer.copyImage())
        XCTAssertNotEqual(pixels(before), pixels(painted))
        XCTAssertLessThan(rig.model.regionUndoBytesRegistered, 1200 * 900 * 4 / 2, "tiles should be sparser than the bbox")
        rig.undo.undo()
        XCTAssertEqual(pixels(try XCTUnwrap(rig.model.layers[0].buffer.copyImage())), pixels(before))
        rig.undo.redo()
        XCTAssertEqual(pixels(try XCTUnwrap(rig.model.layers[0].buffer.copyImage())), pixels(painted))
        rig.undo.undo()
        XCTAssertEqual(pixels(try XCTUnwrap(rig.model.layers[0].buffer.copyImage())), pixels(before))
        XCTAssertFalse(rig.undo.canUndo)
    }

    func testQuickPreviewSizeHeuristic() {
        XCTAssertNil(MainWindowController.quickPreviewSize(sourceLongest: 4000, budget: 5120), "small sources decode fast anyway")
        XCTAssertEqual(MainWindowController.quickPreviewSize(sourceLongest: 6000, budget: 5120), 3000)
        XCTAssertNil(MainWindowController.quickPreviewSize(sourceLongest: 6000, budget: 2880), "sharp decode is already small")
    }

    private func pixels(_ image: CGImage) -> Data { image.dataProvider!.data! as Data }
}
