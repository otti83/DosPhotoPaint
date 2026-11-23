import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Errors surfaced to the user while reading images.
nonisolated enum ImageLoadError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case unreadable(URL, underlying: String?)
    case emptyFile(URL)
    case unsupportedFormat(URL)
    case decodeFailed(URL)
    case tooLarge(URL, width: Int, height: Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            String(localized: "The file “\(url.lastPathComponent)” could not be found.", table: "Documents")
        case .unreadable(let url, _):
            String(localized: "The file “\(url.lastPathComponent)” could not be read. You may not have permission to open it.", table: "Documents")
        case .emptyFile(let url):
            String(localized: "The file “\(url.lastPathComponent)” is empty.", table: "Documents")
        case .unsupportedFormat(let url):
            String(localized: "“\(url.lastPathComponent)” is not in an image format supported on this Mac.", table: "Documents")
        case .decodeFailed(let url):
            String(localized: "“\(url.lastPathComponent)” appears to be damaged and could not be decoded.", table: "Documents")
        case .tooLarge(let url, let w, let h):
            String(localized: "“\(url.lastPathComponent)” (\(w) × \(h) pixels) is too large to edit.", table: "Documents")
        }
    }
}

/// Lightweight properties of an image file, read without decoding pixels.
nonisolated struct ImageSourceInfo: Sendable, Equatable {
    var url: URL
    var type: UTType?
    /// Pixel size *after* applying EXIF orientation (what the user sees).
    var pixelWidth: Int
    var pixelHeight: Int
    /// EXIF orientation 1…8 (1 = up).
    var orientation: CGImagePropertyOrientation
    var frameCount: Int
    var hasAlpha: Bool
    var bitDepth: Int?
    var colorModel: String?
    var profileName: String?
    var fileSize: Int64?

    var isAnimated: Bool { frameCount > 1 }
    var pixelCount: Int { pixelWidth * pixelHeight }
}

/// A fully decoded, orientation-corrected image ready for editing.
nonisolated struct DecodedImage: @unchecked Sendable {
    /// Upright full-resolution image.
    let image: CGImage
    let info: ImageSourceInfo
    /// Raw Image I/O properties of the primary frame (EXIF, GPS, …) for metadata preservation.
    /// `CFDictionary` is immutable, so sharing it across threads is safe.
    let properties: CFDictionary?
}

/// Image I/O based loading. All functions are thread-safe and may be called from any task.
nonisolated enum ImageLoader {
    /// Largest image (in pixels) the editor will materialize (150 MP ≈ 600 MB per RGBA buffer).
    static let maxEditablePixels = 150_000_000

    static func makeSource(_ url: URL) throws -> CGImageSource {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw ImageLoadError.fileNotFound(url) }
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.int64Value == 0 {
            throw ImageLoadError.emptyFile(url)
        }
        guard fm.isReadableFile(atPath: url.path) else { throw ImageLoadError.unreadable(url, underlying: nil) }
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { throw ImageLoadError.unreadable(url, underlying: nil) }
        guard CGImageSourceGetType(src) != nil, CGImageSourceGetCount(src) > 0 else { throw ImageLoadError.unsupportedFormat(url) }
        return src
    }

    /// Reads header information only (fast, no pixel decode).
    static func info(for url: URL) throws -> ImageSourceInfo {
        let src = try makeSource(url)
        return try info(source: src, url: url)
    }

    static func info(source src: CGImageSource, url: URL) throws -> ImageSourceInfo {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            throw ImageLoadError.decodeFailed(url)
        }
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard w > 0, h > 0 else { throw ImageLoadError.decodeFailed(url) }
        let rawOrientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up  // invalid EXIF → up
        let swaps = orientation.swapsDimensions
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
        return ImageSourceInfo(
            url: url,
            type: (CGImageSourceGetType(src) as String?).flatMap { UTType($0) },
            pixelWidth: swaps ? h : w,
            pixelHeight: swaps ? w : h,
            orientation: orientation,
            frameCount: CGImageSourceGetCount(src),
            hasAlpha: (props[kCGImagePropertyHasAlpha] as? Bool) ?? false,
            bitDepth: (props[kCGImagePropertyDepth] as? NSNumber)?.intValue,
            colorModel: props[kCGImagePropertyColorModel] as? String,
            profileName: props[kCGImagePropertyProfileName] as? String,
            fileSize: fileSize
        )
    }

    /// Downsampled, orientation-corrected image for display. `maxPixelSize` is the longest edge.
    /// Never use the result as editing/saving source.
    static func loadDisplayImage(url: URL, maxPixelSize: Int, frame: Int = 0) throws -> CGImage {
        let src = try makeSource(url)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, frame, opts as CFDictionary) else {
            throw ImageLoadError.decodeFailed(url)
        }
        return image
    }

    /// Full-resolution decode with EXIF orientation applied.
    static func loadFullImage(url: URL) throws -> DecodedImage {
        let src = try makeSource(url)
        let info = try info(source: src, url: url)
        guard info.pixelCount <= maxEditablePixels else {
            throw ImageLoadError.tooLarge(url, width: info.pixelWidth, height: info.pixelHeight)
        }
        let opts = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let raw = CGImageSourceCreateImageAtIndex(src, 0, opts) else { throw ImageLoadError.decodeFailed(url) }
        let upright = try ImageTransforms.applyingOrientation(info.orientation, to: raw)
        return DecodedImage(image: upright, info: info, properties: CGImageSourceCopyPropertiesAtIndex(src, 0, nil))
    }
}

nonisolated extension CGImagePropertyOrientation {
    /// Orientations 5…8 rotate by 90°, swapping width and height.
    var swapsDimensions: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored: true
        default: false
        }
    }
}
