import CoreGraphics
import Foundation

/// A whole-image edit applied identically to every layer.
nonisolated enum ImageEdit: Sendable, Equatable {
    case rotateRight
    case rotateLeft
    case rotate180
    case flipHorizontal
    case flipVertical
    case resize(width: Int, height: Int, interpolation: ResampleInterpolation)
    /// Canvas size change without scaling; `offset` is where the old canvas' top-left lands.
    case canvasSize(width: Int, height: Int, offsetX: Int, offsetY: Int)

    /// Size of the result for a canvas of `width × height`.
    func outputSize(width: Int, height: Int) -> (width: Int, height: Int) {
        switch self {
        case .rotateRight, .rotateLeft: (height, width)
        case .rotate180, .flipHorizontal, .flipVertical: (width, height)
        case .resize(let w, let h, _), .canvasSize(let w, let h, _, _): (w, h)
        }
    }
}

nonisolated enum ResampleInterpolation: Sendable, Equatable {
    /// Hard pixel edges (pixel art, exact integer scaling).
    case nearest
    /// Core Graphics `.high` (Lanczos-class filtering): best general quality for photos.
    case high
}

/// Pure `CGImage → CGImage` resampling, rotation and canvas operations. Thread-safe.
///
/// Images are processed in non-flipped Core Graphics contexts (y-up); all transforms below are
/// written for that space but described in terms of the *visual* result.
nonisolated enum ImageResampler {

    /// Largest canvas accepted by resize / canvas size.
    @MainActor static func isValidSize(width: Int, height: Int) -> Bool {
        AppSettings.canvasDimensionRange.contains(width) && AppSettings.canvasDimensionRange.contains(height)
            && width * height <= ImageLoader.maxEditablePixels
    }

    /// Applies `edit` to one layer image. `fill` colours the area newly added by a canvas
    /// size increase (nil = transparent); only the bottom layer receives it.
    static func apply(_ edit: ImageEdit, to image: CGImage, fill: CGColor? = nil) -> CGImage? {
        let w = image.width, h = image.height
        switch edit {
        case .rotateRight: return rotated(image, clockwise: true)
        case .rotateLeft: return rotated(image, clockwise: false)
        case .rotate180: return transformed(image, outW: w, outH: h, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: CGFloat(w), ty: CGFloat(h)))
        case .flipHorizontal: return transformed(image, outW: w, outH: h, CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: CGFloat(w), ty: 0))
        case .flipVertical: return transformed(image, outW: w, outH: h, CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(h)))
        case .resize(let nw, let nh, let q): return resized(image, width: nw, height: nh, interpolation: q)
        case .canvasSize(let nw, let nh, let ox, let oy): return placed(image, width: nw, height: nh, offsetX: ox, offsetY: oy, fill: fill)
        }
    }

    // MARK: - Rotation / flip (exact pixel permutations)

    static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // Output is h × w. y-up space.
        let t = clockwise
            ? CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
            : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        return transformed(image, outW: image.height, outH: image.width, t)
    }

    private static func transformed(_ image: CGImage, outW: Int, outH: Int, _ t: CGAffineTransform) -> CGImage? {
        guard let ctx = ImageTransforms.makeRGBAContext(width: outW, height: outH, colorSpace: image.colorSpace) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.setBlendMode(.copy)
        ctx.concatenate(t)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    // MARK: - Resize

    static func resized(_ image: CGImage, width: Int, height: Int, interpolation: ResampleInterpolation) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard let ctx = ImageTransforms.makeRGBAContext(width: width, height: height, colorSpace: image.colorSpace) else { return nil }
        ctx.interpolationQuality = interpolation == .nearest ? .none : .high
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    // MARK: - Canvas size

    /// Where the old canvas' top-left corner lands in the new canvas for a 3×3 anchor
    /// (`column`/`row` 0…2; 1 = centre). Odd differences round toward the top-left.
    static func anchoredOffset(oldWidth: Int, oldHeight: Int, newWidth: Int, newHeight: Int, column: Int, row: Int) -> (x: Int, y: Int) {
        func axis(_ old: Int, _ new: Int, _ i: Int) -> Int {
            let d = new - old
            switch i {
            case 0: return 0
            case 1: return Int((Double(d) / 2).rounded(.down))
            default: return d
            }
        }
        return (axis(oldWidth, newWidth, column), axis(oldHeight, newHeight, row))
    }

    /// Draws `image` into a new `width × height` image at `(offsetX, offsetY)` (y-down), cropping overflow.
    static func placed(_ image: CGImage, width: Int, height: Int, offsetX: Int, offsetY: Int, fill: CGColor?) -> CGImage? {
        guard let ctx = ImageTransforms.makeRGBAContext(width: width, height: height, colorSpace: image.colorSpace) else { return nil }
        ctx.setBlendMode(.copy)
        if let fill {
            let converted = image.colorSpace.flatMap { fill.converted(to: $0, intent: .defaultIntent, options: nil) } ?? fill
            ctx.setFillColor(converted)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(image, in: CGRect(x: offsetX, y: height - offsetY - image.height, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
