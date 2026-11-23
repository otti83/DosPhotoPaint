import ImageIO
import UniformTypeIdentifiers

/// Which image formats this Mac can actually read / write (queried from Image I/O at runtime).
nonisolated enum ImageTypes {
    static let project = UTType(exportedAs: "com.dosphotopaint.dpp", conformingTo: .package)

    /// Formats the app declares in Info.plist (ordered for UI).
    static let declaredReadable: [UTType] = [.png, .jpeg, .heic, .heif, .bmp, .tiff, .gif, .webP]
    static let declaredWritable: [UTType] = [.png, .jpeg, .heic, .tiff, .bmp]

    /// Declared types the OS decoder supports. WebP etc. only appear if Image I/O can decode them.
    static let readable: [UTType] = {
        let ids = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        return declaredReadable.filter { ids.contains($0.identifier) }
    }()

    /// Declared types the OS encoder supports (HEIC only where the OS can encode it).
    static let writable: [UTType] = {
        let ids = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return declaredWritable.filter { ids.contains($0.identifier) }
    }()

    static func isReadableImage(_ type: UTType) -> Bool {
        readable.contains { type.conforms(to: $0) }
    }

    static func isReadableImage(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return isReadableImage(type)
    }

    static func isWritable(_ type: UTType) -> Bool {
        writable.contains { type.conforms(to: $0) }
    }

    static func supportsAlpha(_ type: UTType) -> Bool {
        !(type.conforms(to: .jpeg) || type.conforms(to: .bmp))
    }

    static func isLossy(_ type: UTType) -> Bool {
        type.conforms(to: .jpeg) || type.conforms(to: .heic) || type.conforms(to: .heif)
    }
}
