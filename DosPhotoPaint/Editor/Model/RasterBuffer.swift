import CoreGraphics
import Foundation

/// Release callback of the zero-copy `CGDataProvider` views. Core Graphics / Core Animation call it
/// on their own render threads when the last reference to a view image goes away, so it must not
/// be main-actor isolated (a closure literal here would inherit the module's MainActor default and
/// trap with a dispatch_assert_queue failure on that thread). The memory is owned by the buffer.
private nonisolated func releaseAliasedPixels(_ info: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer, _ size: Int) {}

/// An 8-bit RGBA premultiplied bitmap.
///
/// Coordinate convention: **y-down pixel coordinates** (origin top-left), the same as
/// `CanvasView`. The context's CTM is flipped once at creation so paths and rects can be
/// drawn directly in pixel coordinates. Use `CGContext.drawUpright(_:in:)` to draw
/// images (CGContext.draw would otherwise render them upside-down in the flipped space).
///
/// Memory rows are stored top-first, so a pixel rect maps directly onto memory.
final class RasterBuffer {
    let width: Int
    let height: Int
    let colorSpace: CGColorSpace
    let context: CGContext

    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    var size: CGSize { CGSize(width: width, height: height) }
    var bytesPerRow: Int { context.bytesPerRow }
    var byteCount: Int { bytesPerRow * height }

    /// Creates a transparent buffer. Returns nil if the bitmap cannot be allocated.
    init?(width: Int, height: Int, colorSpace: CGColorSpace) {
        guard width > 0, height > 0,
              let ctx = ImageTransforms.makeRGBAContext(width: width, height: height, colorSpace: colorSpace)
        else { return nil }
        self.width = width
        self.height = height
        self.colorSpace = ctx.colorSpace ?? colorSpace
        self.context = ctx
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.clear(bounds)
    }

    /// Creates a buffer holding `image` (drawn at 0,0 without scaling).
    convenience init?(image: CGImage, colorSpace: CGColorSpace? = nil) {
        let space = colorSpace ?? image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        self.init(width: image.width, height: image.height, colorSpace: space)
        context.saveGState()
        context.setBlendMode(.copy)
        context.drawUpright(image, in: bounds)
        context.restoreGState()
    }

    /// Deep copy.
    func copy() -> RasterBuffer? {
        guard let dup = RasterBuffer(width: width, height: height, colorSpace: colorSpace),
              let src = context.data, let dst = dup.context.data else { return nil }
        if dup.bytesPerRow == bytesPerRow {
            dst.copyMemory(from: src, byteCount: byteCount)
        } else {
            for y in 0..<height {
                (dst + y * dup.bytesPerRow).copyMemory(from: src + y * bytesPerRow, byteCount: width * 4)
            }
        }
        return dup
    }

    func fill(_ color: CGColor, in rect: CGRect? = nil) {
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor(color)
        context.fill(rect ?? bounds)
        context.restoreGState()
    }

    func clear(_ rect: CGRect? = nil) {
        context.clear(rect ?? bounds)
    }

    /// Integral pixel rect clipped to the buffer.
    func clamp(_ rect: CGRect) -> CGRect {
        guard !rect.isNull, !rect.isEmpty else { return .null }
        let r = rect.integral.intersection(bounds)
        return r.isEmpty ? .null : r
    }

    /// Calls `body` with a **zero-copy** image view of `rect`. The image is only valid inside
    /// `body` and must not escape (it aliases the live pixel memory).
    func withImage<R>(in rect: CGRect? = nil, _ body: (CGImage) -> R) -> R? {
        let r = clamp(rect ?? bounds)
        guard !r.isNull, let base = context.data else { return nil }
        let x = Int(r.minX), y = Int(r.minY), w = Int(r.width), h = Int(r.height)
        let start = base + y * bytesPerRow + x * 4
        let length = (h - 1) * bytesPerRow + w * 4
        guard let provider = CGDataProvider(dataInfo: nil, data: start, size: length, releaseData: releaseAliasedPixels),
              let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return body(image)
    }

    /// Independent copy of the pixels in `rect` (safe to keep, e.g. for undo).
    func copyImage(in rect: CGRect? = nil) -> CGImage? {
        let r = clamp(rect ?? bounds)
        guard !r.isNull, let base = context.data else { return nil }
        let x = Int(r.minX), y = Int(r.minY), w = Int(r.width), h = Int(r.height)
        let rowBytes = w * 4
        var data = Data(count: rowBytes * h)
        data.withUnsafeMutableBytes { dst in
            guard let d = dst.baseAddress else { return }
            for row in 0..<h {
                (d + row * rowBytes).copyMemory(from: base + (y + row) * bytesPerRow + x * 4, byteCount: rowBytes)
            }
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Replaces the pixels of `rect` with `image` exactly (copy blend, no scaling).
    func replace(_ rect: CGRect, with image: CGImage) {
        context.saveGState()
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.drawUpright(image, in: CGRect(x: rect.minX, y: rect.minY, width: CGFloat(image.width), height: CGFloat(image.height)))
        context.restoreGState()
    }

    /// Direct pixel access (RGBA premultiplied, rows top-first).
    func withMutablePixels<R>(_ body: (UnsafeMutablePointer<UInt8>, _ bytesPerRow: Int) -> R) -> R? {
        guard let data = context.data else { return nil }
        return body(data.assumingMemoryBound(to: UInt8.self), bytesPerRow)
    }

    /// Premultiplied RGBA at a pixel, or nil if outside.
    func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, y >= 0, x < width, y < height, let data = context.data else { return nil }
        let p = data.assumingMemoryBound(to: UInt8.self) + y * bytesPerRow + x * 4
        return (p[0], p[1], p[2], p[3])
    }
}

extension CGContext {
    /// Draws `image` upright into `rect` when the context's user space is y-down (flipped).
    nonisolated func drawUpright(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: 0, y: rect.minY + rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: rect)
        restoreGState()
    }
}
