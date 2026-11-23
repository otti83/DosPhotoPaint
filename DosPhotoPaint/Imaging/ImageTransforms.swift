import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ImageTransformError: Error {
    case contextCreationFailed
}

/// Pure pixel transforms on `CGImage` values.
nonisolated enum ImageTransforms {
    /// 8-bit RGBA premultiplied context in `colorSpace` (falls back to sRGB for non-RGB spaces).
    static func makeRGBAContext(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        func make(_ space: CGColorSpace) -> CGContext? {
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        if let space = colorSpace, space.model == .rgb, let ctx = make(space) { return ctx }
        // Extended-range / linear spaces (HDR sources) have no 8-bit bitmap format: use sRGB.
        return make(srgb)
    }

    /// Returns an upright copy of `image` given its EXIF orientation. `.up` returns the input unchanged.
    static func applyingOrientation(_ orientation: CGImagePropertyOrientation, to image: CGImage) throws -> CGImage {
        if orientation == .up { return image }
        let w = image.width, h = image.height
        let outW = orientation.swapsDimensions ? h : w
        let outH = orientation.swapsDimensions ? w : h
        guard let ctx = makeRGBAContext(width: outW, height: outH, colorSpace: image.colorSpace) else {
            throw ImageTransformError.contextCreationFailed
        }
        ctx.interpolationQuality = .none
        // Core Graphics origin is bottom-left; transforms below map the stored image to upright.
        var t = CGAffineTransform.identity
        let W = CGFloat(outW), H = CGFloat(outH)
        switch orientation {
        case .up: break
        case .upMirrored: t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: W, ty: 0)
        case .down: t = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: W, ty: H)
        case .downMirrored: t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: H)
        // EXIF 5…8, derived from the display transforms (y-down: 5 transpose, 6 rotate 90° CW,
        // 7 transverse, 8 rotate 90° CCW) converted to Core Graphics' y-up space.
        case .leftMirrored: t = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: W, ty: H)   // 5
        case .right: t = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: H)           // 6
        case .rightMirrored: t = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)    // 7
        case .left: t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: W, ty: 0)            // 8
        @unknown default: break
        }
        ctx.concatenate(t)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { throw ImageTransformError.contextCreationFailed }
        return out
    }
}
