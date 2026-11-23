import AppKit
import ImageIO

/// Reading/writing images on the general pasteboard.
enum ClipboardImage {
    static func hasImage(_ pb: NSPasteboard = .general) -> Bool {
        pb.canReadObject(forClasses: [NSImage.self], options: nil)
            || pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ImageTypes.readable.map(\.identifier)])
    }

    /// First image on the pasteboard as a CGImage (orientation-corrected for files).
    static func readImage(_ pb: NSPasteboard = .general) -> CGImage? {
        // Prefer image files (full quality, EXIF orientation applied by the loader).
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: ImageTypes.readable.map(\.identifier)]) as? [URL],
           let url = urls.first, let decoded = try? ImageLoader.loadFullImage(url: url) {
            return decoded.image
        }
        // Raw image data (PNG/TIFF from screenshots and other apps).
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pb.data(forType: type),
               let src = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return image
            }
        }
        if let image = (pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first {
            var rect = CGRect(origin: .zero, size: image.size)
            return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return nil
    }

    /// Writes an image as PNG + TIFF (TIFF for older apps).
    static func write(_ image: CGImage, to pb: NSPasteboard = .general) {
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }
}
