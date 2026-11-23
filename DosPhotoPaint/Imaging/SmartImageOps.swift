import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// On-device "smart" image operations built on Apple frameworks only (no network, no bundled
/// models): subject masks from Vision and Core Image's automatic enhancement. Pure functions on
/// `CGImage`s, safe to call off the main thread.
nonisolated enum SmartImageOps {

    enum Failure: Error, Equatable {
        /// Vision found no foreground subject.
        case noSubject
        /// A bitmap could not be allocated or the analysis failed.
        case failed
    }

    // MARK: - Subject mask

    /// Per-pixel subject coverage (0…1, rows top-first, `width × height` of `image`).
    struct Mask: Sendable {
        let width: Int
        let height: Int
        let values: [Float]
    }

    /// Foreground mask of `image` (all detected subject instances), the same size as the image.
    static func subjectMask(of image: CGImage) throws -> Mask {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.failed
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw Failure.noSubject }
        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        } catch {
            throw Failure.failed
        }
        return try mask(from: buffer, width: image.width, height: image.height)
    }

    /// Reads a one-component float mask. Vision returns it at the image's size; anything else
    /// (unexpected format or size) is treated as a failure rather than guessed at.
    static func mask(from buffer: CVPixelBuffer, width: Int, height: Int) throws -> Mask {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height else { throw Failure.failed }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw Failure.failed }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var values = [Float](repeating: 0, count: width * height)
        values.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in 0..<width { out[y * width + x] = min(max(row[x], 0), 1) }
            }
        }
        return Mask(width: width, height: height, values: values)
    }

    /// `image` with every pixel's coverage multiplied by `mask` (background becomes transparent).
    /// The result is RGBA premultiplied in `colorSpace`, so colours are not converted.
    static func applying(_ mask: Mask, to image: CGImage, colorSpace: CGColorSpace) throws -> CGImage {
        guard mask.width == image.width, mask.height == image.height,
              let ctx = ImageTransforms.makeRGBAContext(width: image.width, height: image.height, colorSpace: colorSpace)
        else { throw Failure.failed }
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = ctx.data else { throw Failure.failed }
        let rowBytes = ctx.bytesPerRow
        let px = data.assumingMemoryBound(to: UInt8.self)
        mask.values.withUnsafeBufferPointer { m in
            // Bitmap memory is top-first, like the mask.
            for y in 0..<image.height {
                let row = px + y * rowBytes
                for x in 0..<image.width {
                    let k = m[y * image.width + x]
                    if k >= 1 { continue }
                    let p = row + x * 4
                    // Premultiplied: scaling all four channels keeps the colour and changes the coverage.
                    for c in 0..<4 { p[c] = UInt8((Float(p[c]) * k).rounded()) }
                }
            }
        }
        guard let out = ctx.makeImage() else { throw Failure.failed }
        return out
    }

    // MARK: - Auto enhance

    /// Core Image's automatic adjustments (exposure, contrast, colour; no red-eye or crop).
    /// Transparency is preserved. Returns the input unchanged when no adjustment is suggested.
    static func autoEnhanced(_ image: CGImage, colorSpace: CGColorSpace) throws -> CGImage {
        let input = CIImage(cgImage: image)
        let filters = input.autoAdjustmentFilters(options: [.redEye: false, .crop: false, .level: false])
        guard !filters.isEmpty else { return image }
        var output = input
        for filter in filters {
            filter.setValue(output, forKey: kCIInputImageKey)
            guard let next = filter.outputImage else { throw Failure.failed }
            output = next
        }
        let space = colorSpace.model == .rgb ? colorSpace : CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(output.cropped(to: input.extent), from: input.extent,
                                                   format: .RGBA8, colorSpace: space) else { throw Failure.failed }
        return rendered
    }
}
