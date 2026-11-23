import XCTest
import CoreGraphics
@testable import DosPhotoPaint

@MainActor
final class TransformsTests: AppTestCase {

    // MARK: Helpers

    private var retainedUndoManagers: [UndoManager] = []

    /// Deterministic image with a distinct premultiplied-safe pixel at every position (alpha 255).
    private func makeImage(_ w: Int, _ h: Int) -> CGImage {
        let buffer = RasterBuffer(width: w, height: h, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        buffer.withMutablePixels { p, bpr in
            for y in 0..<h { for x in 0..<w {
                let o = y * bpr + x * 4
                p[o] = UInt8(x * 7 % 256); p[o + 1] = UInt8(y * 13 % 256); p[o + 2] = UInt8((x + y) * 3 % 256); p[o + 3] = 255
            } }
        }
        return buffer.copyImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4))
    }

    private func px(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let w = image.width
        let p = pixels(image)
        return Array(p[(y * w + x) * 4..<(y * w + x) * 4 + 4])
    }

    private func makeCanvas(_ w: Int, _ h: Int) -> CanvasModel {
        let c = CanvasModel(image: makeImage(w, h))!
        let manager = UndoManager()
        manager.groupsByEvent = false
        retainedUndoManagers.append(manager)   // CanvasModel.undoManager is weak
        c.undoManager = manager
        return c
    }

    private func grouped(_ c: CanvasModel, _ body: () -> Void) {
        c.undoManager?.beginUndoGrouping(); body(); c.undoManager?.endUndoGrouping()
    }

    private func edit(_ c: CanvasModel, _ e: ImageEdit, background: CGColor? = nil) async throws {
        c.undoManager?.beginUndoGrouping()
        try await c.apply(e, actionName: "t", background: background)
        c.undoManager?.endUndoGrouping()
    }

    // MARK: Rotation / flip

    func testRotateRightMapsPixels() {
        let img = makeImage(5, 3)
        let r = ImageResampler.apply(.rotateRight, to: img)!
        XCTAssertEqual(r.width, 3); XCTAssertEqual(r.height, 5)
        // y-down: old (x, y) -> new (H-1-y, x)
        for y in 0..<3 { for x in 0..<5 { XCTAssertEqual(px(r, 3 - 1 - y, x), px(img, x, y)) } }
        let l = ImageResampler.apply(.rotateLeft, to: img)!
        // old (x, y) -> new (y, W-1-x)
        for y in 0..<3 { for x in 0..<5 { XCTAssertEqual(px(l, y, 5 - 1 - x), px(img, x, y)) } }
    }

    func testFourRotationsAreIdentity() {
        let img = makeImage(37, 23)
        var cur = img
        for _ in 0..<4 { cur = ImageResampler.apply(.rotateRight, to: cur)! }
        XCTAssertEqual(pixels(cur), pixels(img))
        cur = img
        for _ in 0..<4 { cur = ImageResampler.apply(.rotateLeft, to: cur)! }
        XCTAssertEqual(pixels(cur), pixels(img))
        let twice = ImageResampler.apply(.rotate180, to: ImageResampler.apply(.rotate180, to: img)!)!
        XCTAssertEqual(pixels(twice), pixels(img))
        let r180 = ImageResampler.apply(.rotateRight, to: ImageResampler.apply(.rotateRight, to: img)!)!
        XCTAssertEqual(pixels(ImageResampler.apply(.rotate180, to: img)!), pixels(r180))
    }

    func testFlipTwiceIsIdentityAndMirrors() {
        let img = makeImage(11, 7)
        for e in [ImageEdit.flipHorizontal, .flipVertical] {
            let once = ImageResampler.apply(e, to: img)!
            XCTAssertEqual(pixels(ImageResampler.apply(e, to: once)!), pixels(img))
            XCTAssertNotEqual(pixels(once), pixels(img))
        }
        let h = ImageResampler.apply(.flipHorizontal, to: img)!
        XCTAssertEqual(px(h, 0, 2), px(img, 10, 2))
        let v = ImageResampler.apply(.flipVertical, to: img)!
        XCTAssertEqual(px(v, 3, 0), px(img, 3, 6))
    }

    // MARK: Resize

    func testResizeDimensionsAndNearestExactness() {
        let img = makeImage(4, 3)
        let up = ImageResampler.resized(img, width: 8, height: 6, interpolation: .nearest)!
        XCTAssertEqual(up.width, 8); XCTAssertEqual(up.height, 6)
        for y in 0..<6 { for x in 0..<8 { XCTAssertEqual(px(up, x, y), px(img, x / 2, y / 2)) } }
        let down = ImageResampler.resized(up, width: 4, height: 3, interpolation: .nearest)!
        XCTAssertEqual(pixels(down), pixels(img))
        let hq = ImageResampler.resized(img, width: 9, height: 5, interpolation: .high)!
        XCTAssertEqual(hq.width, 9); XCTAssertEqual(hq.height, 5)
    }

    func testResizeAppliesToAllLayersWithUndo() async throws {
        let c = makeCanvas(6, 4)
        grouped(c) { c.addLayer() }
        try await edit(c, .resize(width: 12, height: 8, interpolation: .nearest))
        XCTAssertEqual(c.width, 12); XCTAssertEqual(c.height, 8)
        XCTAssertTrue(c.layers.allSatisfy { $0.buffer.width == 12 && $0.buffer.height == 8 })
        c.undoManager?.undo()
        XCTAssertEqual(c.width, 6); XCTAssertEqual(c.layers.count, 2)
        c.undoManager?.redo()
        XCTAssertEqual(c.width, 12)
    }

    // MARK: Canvas size

    func testAnchorOffsets() {
        func off(_ c: Int, _ r: Int, _ nw: Int, _ nh: Int) -> (Int, Int) {
            let o = ImageResampler.anchoredOffset(oldWidth: 10, oldHeight: 10, newWidth: nw, newHeight: nh, column: c, row: r)
            return (o.x, o.y)
        }
        XCTAssertTrue(off(0, 0, 20, 30) == (0, 0))
        XCTAssertTrue(off(2, 2, 20, 30) == (10, 20))
        XCTAssertTrue(off(1, 1, 20, 30) == (5, 10))
        XCTAssertTrue(off(2, 0, 4, 4) == (-6, 0))
        XCTAssertTrue(off(1, 1, 5, 5) == (-3, -3))
    }

    func testCanvasSizeAnchorPlacementFillAndUndo() async throws {
        let c = makeCanvas(4, 4)
        grouped(c) { c.addLayer() }
        let bottom = c.layers[0].buffer.copyImage()!
        let off = ImageResampler.anchoredOffset(oldWidth: 4, oldHeight: 4, newWidth: 8, newHeight: 6, column: 2, row: 2)
        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        try await edit(c, .canvasSize(width: 8, height: 6, offsetX: off.x, offsetY: off.y), background: red)
        XCTAssertEqual(c.width, 8); XCTAssertEqual(c.height, 6)
        let b = c.layers[0].buffer.copyImage()!
        XCTAssertEqual(px(b, 4, 2), px(bottom, 0, 0))      // old top-left lands at (4,2)
        XCTAssertEqual(px(b, 7, 5), px(bottom, 3, 3))
        XCTAssertEqual(px(b, 0, 0), [255, 0, 0, 255])      // new area: background colour
        let upper = c.layers[1].buffer.copyImage()!
        XCTAssertEqual(px(upper, 0, 0), [0, 0, 0, 0])      // upper layer: transparent
        c.undoManager?.undo()
        XCTAssertEqual(c.width, 4)
        XCTAssertEqual(pixels(c.layers[0].buffer.copyImage()!), pixels(bottom))
        // Shrinking crops.
        let off2 = ImageResampler.anchoredOffset(oldWidth: 4, oldHeight: 4, newWidth: 2, newHeight: 2, column: 2, row: 2)
        try await edit(c, .canvasSize(width: 2, height: 2, offsetX: off2.x, offsetY: off2.y))
        XCTAssertEqual(px(c.layers[0].buffer.copyImage()!, 0, 0), px(bottom, 2, 2))
    }

    // MARK: Model-level rotate / flip undo

    func testRotateAndFlipUndoRedo() async throws {
        let c = makeCanvas(9, 5)
        let original = pixels(c.layers[0].buffer.copyImage()!)
        for e in [ImageEdit.rotateRight, .rotateLeft, .rotate180, .flipHorizontal, .flipVertical] {
            try await edit(c, e)
            c.undoManager?.undo()
            XCTAssertEqual(c.width, 9)
            XCTAssertEqual(pixels(c.layers[0].buffer.copyImage()!), original)
            c.undoManager?.redo()
            c.undoManager?.undo()
        }
        try await edit(c, .rotateRight)
        XCTAssertEqual(c.width, 5); XCTAssertEqual(c.height, 9)
        c.undoManager?.undo()
        XCTAssertEqual(c.width, 9)
    }

    func testSelectionFollowsRotation() async throws {
        let c = makeCanvas(10, 4)
        c.setSelection(.rect(CGRect(x: 0, y: 0, width: 2, height: 1)), undoable: false)
        try await edit(c, .rotateRight)
        // old (0..2, 0..1) -> new x in (3..4), y in (0..2)
        XCTAssertEqual(c.selection?.bounds, CGRect(x: 3, y: 0, width: 1, height: 2))
        c.undoManager?.undo()
        XCTAssertEqual(c.selection?.bounds, CGRect(x: 0, y: 0, width: 2, height: 1))
    }

    // MARK: Layers

    func testMergeDownRespectsOpacityAndUndo() {
        let c = makeCanvas(2, 2)
        c.layers[0].buffer.fill(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        grouped(c) { c.addLayer() }
        let top = c.layers[1]
        top.buffer.fill(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        c.setProperties(LayerProperties(name: top.name, isVisible: true, opacity: 0.5), of: top.id)
        c.undoManager?.beginUndoGrouping()
        XCTAssertTrue(c.mergeActiveLayerDown())
        c.undoManager?.endUndoGrouping()
        XCTAssertEqual(c.layers.count, 1)
        let p = c.layers[0].buffer.pixel(x: 0, y: 0)!
        XCTAssertEqual(Int(p.r), 128, accuracy: 1)
        XCTAssertEqual(p.a, 255)
        c.undoManager?.undo()
        XCTAssertEqual(c.layers.count, 2)
        XCTAssertEqual(c.layers[0].buffer.pixel(x: 0, y: 0)!.r, 0)
        XCTAssertEqual(c.layers[1].opacity, 0.5)
    }

    func testMergeHiddenLayerContributesNothing() {
        let c = makeCanvas(2, 2)
        c.layers[0].buffer.fill(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        grouped(c) { c.addLayer() }
        c.layers[1].buffer.fill(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        c.layers[1].isVisible = false
        grouped(c) { c.mergeActiveLayerDown() }
        XCTAssertEqual(c.layers[0].buffer.pixel(x: 0, y: 0)!.r, 0)
    }

    func testLayerOpsUndoRedo() {
        let c = makeCanvas(3, 3)
        let um = c.undoManager!
        func step(_ body: () -> Void) { um.beginUndoGrouping(); body(); um.endUndoGrouping() }
        let base = c.layers[0].id
        step { c.addLayer() }
        XCTAssertEqual(c.layers.count, 2)
        let added = c.activeLayerID
        step { c.duplicateActiveLayer() }
        XCTAssertEqual(c.layers.count, 3)
        step { c.moveActiveLayer(by: -1) }
        XCTAssertEqual(c.layers.map(\.id).firstIndex(of: c.activeLayerID), 1)
        step { c.flatten() }
        XCTAssertEqual(c.layers.count, 1)
        XCTAssertEqual(c.layers[0].id, base)
        um.undo(); XCTAssertEqual(c.layers.count, 3)
        um.undo(); XCTAssertEqual(c.layers.map(\.id).firstIndex(of: c.activeLayerID), 2)
        um.undo(); XCTAssertEqual(c.layers.count, 2)
        step { c.activeLayerID = added; c.deleteActiveLayer() }
        XCTAssertEqual(c.layers.count, 1)
        um.undo(); XCTAssertEqual(c.layers.count, 2)
        um.redo(); XCTAssertEqual(c.layers.count, 1)
        XCTAssertFalse(c.deleteActiveLayer())
    }

    func testReorderAndProperties() {
        let c = makeCanvas(2, 2)
        let um = c.undoManager!
        grouped(c) { c.addLayer(); c.addLayer() }
        let ids = c.layers.map(\.id)
        um.beginUndoGrouping(); c.reorderLayers(bottomToTop: [ids[2], ids[0], ids[1]]); um.endUndoGrouping()
        XCTAssertEqual(c.layers.map(\.id), [ids[2], ids[0], ids[1]])
        um.undo()
        XCTAssertEqual(c.layers.map(\.id), ids)

        let l = c.layers[1]
        let old = c.properties(of: l.id)!
        var new = old; new.name = "Renamed"; new.opacity = 0.3; new.isVisible = false
        um.beginUndoGrouping(); c.setProperties(new, of: l.id, undoFrom: old); um.endUndoGrouping()
        XCTAssertEqual(l.name, "Renamed")
        um.undo()
        XCTAssertEqual(c.properties(of: l.id), old)
        um.redo()
        XCTAssertEqual(c.properties(of: l.id), new)
    }
}

@MainActor
final class TransformsFloatingTests: AppTestCase {
    /// Floating content present when an edit starts is merged (not lost) before the layers are replaced.
    func testRotateCommitsFloatingContent() async throws {
        let c = CanvasModel(width: 4, height: 2, background: CGColor(red: 0, green: 0, blue: 0, alpha: 1))!
        let manager = UndoManager()
        c.undoManager = manager
        let red = CanvasModel(width: 1, height: 1, background: CGColor(red: 1, green: 0, blue: 0, alpha: 1))!.layers[0].buffer.copyImage()!
        c.floating = FloatingContent(layerID: c.activeLayerID, image: red, transform: .identity)
        try await c.apply(.rotateRight, actionName: "t")
        XCTAssertNil(c.floating)
        XCTAssertEqual(c.width, 2)
        let p = c.layers[0].buffer.pixel(x: 1, y: 0)!   // (0,0) rotates clockwise to the top-right
        XCTAssertEqual(p.r, 255)
    }
}

@MainActor
final class EngineReviewColourTests: AppTestCase {
    private func image(in space: CGColorSpace, rgba: [UInt8]) -> CGImage? {
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func testCanvasFromImageInUnsupportedBitmapColourSpaceFallsBackToSRGB() throws {
        for name in [CGColorSpace.extendedSRGB, CGColorSpace.extendedLinearSRGB, CGColorSpace.displayP3, CGColorSpace.adobeRGB1998] {
            guard let space = CGColorSpace(name: name),
                  let img = image(in: space, rgba: [200, 100, 50, 255]) else { continue }
            let model = CanvasModel(image: img)
            XCTAssertNotNil(model, "\(name) must stay editable")
            XCTAssertEqual(model?.width, 1)
        }
    }

    func testP3CanvasStrokeColourIsConvertedNotReinterpreted() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let model = try XCTUnwrap(CanvasModel(width: 8, height: 8, colorSpace: p3, background: CGColor(gray: 1, alpha: 1)))
        let layer = model.layers[0]
        // sRGB pure red is NOT (255,0,0) in Display P3.
        layer.buffer.fill(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor)
        let px = try XCTUnwrap(layer.buffer.pixel(x: 1, y: 1))
        XCTAssertLessThan(Int(px.r), 255)
        XCTAssertGreaterThan(Int(px.g), 0)
        // The eyedropper reads it back as the same sRGB colour.
        let c = try XCTUnwrap(model.compositeColor(atX: 1, y: 1))
        let back = try XCTUnwrap(NSColor(cgColor: CGColor(colorSpace: p3, components: [c.r, c.g, c.b, c.a].map { CGFloat($0) })!)?.usingColorSpace(.sRGB))
        XCTAssertEqual(back.redComponent, 1, accuracy: 0.02)
        XCTAssertEqual(back.greenComponent, 0, accuracy: 0.02)
    }
}
