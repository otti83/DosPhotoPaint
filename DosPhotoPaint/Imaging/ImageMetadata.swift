import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Descriptive metadata of an image file for the info panel. Every optional field is only set
/// when the file really contains it — nothing is derived or invented.
nonisolated struct ImageMetadata: Sendable, Equatable {
    var url: URL
    var fileName: String
    var path: String
    var fileSize: Int64?
    var formatDescription: String?
    var typeIdentifier: String?
    /// Pixel size as displayed (EXIF orientation applied).
    var pixelWidth: Int
    var pixelHeight: Int
    var frameCount: Int
    var colorModel: String?
    var profileName: String?
    var bitDepth: Int?
    var hasAlpha: Bool
    var dpiX: Double?
    var dpiY: Double?
    var creationDate: Date?
    var modificationDate: Date?

    // EXIF / TIFF
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var exposureTime: Double?
    var fNumber: Double?
    var iso: Int?
    var focalLength: Double?
    var dateTaken: Date?

    // GPS (signed decimal degrees, metres above sea level)
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?

    var pixelCount: Int { pixelWidth * pixelHeight }
    var hasGPS: Bool { latitude != nil && longitude != nil }
    var hasExposureInfo: Bool { exposureTime != nil || fNumber != nil || iso != nil || focalLength != nil }

    /// Reads metadata without decoding pixels. Returns nil if the file is not a readable image.
    static func read(from url: URL) -> ImageMetadata? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts), CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let w = int(props[kCGImagePropertyPixelWidth]) ?? 0
        let h = int(props[kCGImagePropertyPixelHeight]) ?? 0
        guard w > 0, h > 0 else { return nil }
        let orientation = int(props[kCGImagePropertyOrientation]).flatMap { CGImagePropertyOrientation(rawValue: UInt32($0)) } ?? .up
        let swaps = orientation.swapsDimensions

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let type = (CGImageSourceGetType(src) as String?)

        var m = ImageMetadata(
            url: url, fileName: url.lastPathComponent, path: url.path,
            fileSize: (attrs?[.size] as? NSNumber)?.int64Value,
            formatDescription: type.flatMap { UTType($0)?.localizedDescription },
            typeIdentifier: type,
            pixelWidth: swaps ? h : w, pixelHeight: swaps ? w : h,
            frameCount: CGImageSourceGetCount(src),
            colorModel: props[kCGImagePropertyColorModel] as? String,
            profileName: props[kCGImagePropertyProfileName] as? String,
            bitDepth: int(props[kCGImagePropertyDepth]),
            hasAlpha: (props[kCGImagePropertyHasAlpha] as? Bool) ?? false,
            dpiX: double(props[kCGImagePropertyDPIWidth]), dpiY: double(props[kCGImagePropertyDPIHeight]),
            creationDate: attrs?[.creationDate] as? Date,
            modificationDate: attrs?[.modificationDate] as? Date)

        m.cameraMake = nonEmpty(tiff[kCGImagePropertyTIFFMake])
        m.cameraModel = nonEmpty(tiff[kCGImagePropertyTIFFModel])
        m.lensModel = nonEmpty(exif[kCGImagePropertyExifLensModel])
        m.exposureTime = double(exif[kCGImagePropertyExifExposureTime]).flatMap { $0 > 0 ? $0 : nil }
        m.fNumber = double(exif[kCGImagePropertyExifFNumber]).flatMap { $0 > 0 ? $0 : nil }
        m.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Any])?.first.flatMap { int($0) }
        m.focalLength = double(exif[kCGImagePropertyExifFocalLength]).flatMap { $0 > 0 ? $0 : nil }
        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            m.dateTaken = parseExifDate(s, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        }

        if var lat = double(gps[kCGImagePropertyGPSLatitude]), var lon = double(gps[kCGImagePropertyGPSLongitude]),
           abs(lat) <= 90, abs(lon) <= 180 {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" { lat = -abs(lat) }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" { lon = -abs(lon) }
            m.latitude = lat
            m.longitude = lon
            if var alt = double(gps[kCGImagePropertyGPSAltitude]) {
                if int(gps[kCGImagePropertyGPSAltitudeRef]) == 1 { alt = -abs(alt) }
                m.altitude = alt
            }
        }
        return m
    }

    // MARK: Helpers

    private static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
    private static func double(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    private static func nonEmpty(_ v: Any?) -> String? {
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// EXIF dates are "yyyy:MM:dd HH:mm:ss" in local camera time; `offset` is "+09:00" when recorded.
    static func parseExifDate(_ string: String, offset: String?) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let offset, offset.count == 6, let tz = TimeZone(iso8601Offset: offset) {
            f.timeZone = tz
        }
        return f.date(from: string)
    }
}

nonisolated private extension TimeZone {
    /// "+09:00" / "-05:30" → fixed-offset zone.
    init?(iso8601Offset s: String) {
        let chars = Array(s)
        guard chars.count == 6, chars[0] == "+" || chars[0] == "-", chars[3] == ":",
              let h = Int(String(chars[1...2])), let m = Int(String(chars[4...5])) else { return nil }
        let seconds = (h * 3600 + m * 60) * (chars[0] == "-" ? -1 : 1)
        self.init(secondsFromGMT: seconds)
    }
}
