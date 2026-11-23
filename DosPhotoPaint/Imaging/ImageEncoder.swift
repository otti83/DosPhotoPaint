import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageEncodeError: LocalizedError, Sendable {
    case unsupportedType(String)
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let t): String(localized: "This Mac cannot save images of type “\(t)”.", table: "Documents")
        case .encodeFailed(let t): String(localized: "The image could not be encoded as “\(t)”.", table: "Documents")
        }
    }
}

/// Straight (non-premultiplied) sRGB colour, Sendable.
nonisolated struct RGBAColor: Sendable, Equatable, Codable {
    var r: Double, g: Double, b: Double, a: Double
    static let white = RGBAColor(r: 1, g: 1, b: 1, a: 1)
    static let black = RGBAColor(r: 0, g: 0, b: 0, a: 1)
    static let clear = RGBAColor(r: 0, g: 0, b: 0, a: 0)
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

nonisolated struct EncodeOptions: @unchecked Sendable {
    /// 0…1, lossy formats only.
    var quality: Double = 0.9
    /// Composited under the image for formats without alpha (JPEG, BMP). nil → white.
    var matteColor: RGBAColor = .white
    /// Source metadata (EXIF/IPTC/…) to carry over. Orientation is always reset to "up",
    /// pixel dimensions are always taken from the new image. Immutable CFDictionary.
    var metadata: CFDictionary?
    var keepMetadata = true
    var stripGPS = true
    /// Convert pixels to sRGB before writing.
    var convertToSRGB = false
}

/// Image I/O based encoding. Thread-safe.
nonisolated enum ImageEncoder {
    static func encode(_ image: CGImage, as type: UTType, options: EncodeOptions = EncodeOptions()) throws -> Data {
        guard ImageTypes.isWritable(type) || type == .png else { throw ImageEncodeError.unsupportedType(type.localizedDescription ?? type.identifier) }
        var image = image
        if options.convertToSRGB, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
           image.colorSpace?.name != CGColorSpace.sRGB,
           let converted = image.copy(colorSpace: srgb) ?? redraw(image, matte: nil, colorSpace: srgb) {
            image = converted
        }
        if !ImageTypes.supportsAlpha(type) {
            image = redraw(image, matte: options.matteColor, colorSpace: image.colorSpace) ?? image
        }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw ImageEncodeError.unsupportedType(type.identifier)
        }
        var props: [CFString: Any] = [:]
        if options.keepMetadata, let meta = options.metadata as? [CFString: Any] {
            props = meta
            props.removeValue(forKey: kCGImagePropertyPixelWidth)
            props.removeValue(forKey: kCGImagePropertyPixelHeight)
            props.removeValue(forKey: kCGImagePropertyOrientation)
            props.removeValue(forKey: kCGImagePropertyProfileName)
            props.removeValue(forKey: kCGImagePropertyDepth)
            props.removeValue(forKey: kCGImagePropertyHasAlpha)
            props.removeValue(forKey: kCGImagePropertyColorModel)
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
                props[kCGImagePropertyTIFFDictionary] = tiff
            }
            if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
                props[kCGImagePropertyExifDictionary] = exif
            }
        }
        if options.stripGPS || !options.keepMetadata { props.removeValue(forKey: kCGImagePropertyGPSDictionary) }
        props[kCGImagePropertyOrientation] = 1
        if ImageTypes.isLossy(type) {
            props[kCGImageDestinationLossyCompressionQuality] = min(max(options.quality, 0), 1)
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageEncodeError.encodeFailed(type.identifier) }
        return data as Data
    }

    /// Redraws `image` (optionally over an opaque matte) into an RGBA8 bitmap.
    static func redraw(_ image: CGImage, matte: RGBAColor?, colorSpace: CGColorSpace?) -> CGImage? {
        guard let ctx = ImageTransforms.makeRGBAContext(width: image.width, height: image.height, colorSpace: colorSpace) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if let matte {
            ctx.setFillColor(matte.cgColor)
            ctx.fill(rect)
        }
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }
}
