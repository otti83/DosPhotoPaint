import SwiftUI

/// Model behind the image info panel.
@Observable
final class ImageInfoModel {
    var metadata: ImageMetadata?
    var isLoading = false
    /// Size shown when there is no file (untitled canvas).
    var fallbackSize: CGSize?
    /// The canvas has unsaved edits, so file facts may differ from what is on screen.
    var isEdited = false
}

/// Image info: only fields that exist in the file are listed.
struct ImageInfoView: View {
    let model: ImageInfoModel

    var body: some View {
        Group {
            if let m = model.metadata {
                Form {
                    if model.isEdited {
                        Section { Text("Unsaved changes: this information describes the file on disk.", tableName: "Viewer").foregroundStyle(.secondary) }
                    }
                    fileSection(m)
                    imageSection(m)
                    if m.cameraMake != nil || m.cameraModel != nil || m.lensModel != nil || m.hasExposureInfo || m.dateTaken != nil {
                        cameraSection(m)
                    }
                    if m.hasGPS { gpsSection(m) }
                }
                .formStyle(.grouped)
            } else if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let size = model.fallbackSize {
                Form {
                    Section { row("Size", "\(Int(size.width)) × \(Int(size.height)) px") }
                }.formStyle(.grouped)
            } else {
                Text("No information available.", tableName: "Viewer").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 300, minHeight: 240)
    }

    // MARK: Sections

    private func fileSection(_ m: ImageMetadata) -> some View {
        Section {
            row("Name", m.fileName)
            row("Path", m.path)
            if let size = m.fileSize {
                row("File size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let f = m.formatDescription ?? m.typeIdentifier { row("Format", f) }
            if let d = m.creationDate { row("Created", d.formatted(date: .abbreviated, time: .shortened)) }
            if let d = m.modificationDate { row("Modified", d.formatted(date: .abbreviated, time: .shortened)) }
        }
    }

    private func imageSection(_ m: ImageMetadata) -> some View {
        Section {
            row("Dimensions", "\(m.pixelWidth) × \(m.pixelHeight) px")
            row("Pixels", Self.megapixels(m.pixelCount))
            if let p = m.profileName ?? m.colorModel { row("Color space", p) }
            if let b = m.bitDepth { row("Bit depth", String(localized: "\(b) bits per channel", table: "Viewer")) }
            row("Alpha", m.hasAlpha ? String(localized: "Yes", table: "Viewer") : String(localized: "No", table: "Viewer"))
            if m.frameCount > 1 { row("Frames", "\(m.frameCount)") }
            if let x = m.dpiX, let y = m.dpiY, x > 0, y > 0 {
                row("Resolution", x == y ? "\(Int(x.rounded())) dpi" : "\(Int(x.rounded())) × \(Int(y.rounded())) dpi")
            }
        }
    }

    private func cameraSection(_ m: ImageMetadata) -> some View {
        Section {
            if let make = m.cameraMake { row("Camera make", make) }
            if let model = m.cameraModel { row("Camera model", model) }
            if let lens = m.lensModel { row("Lens", lens) }
            if let d = m.dateTaken { row("Date taken", d.formatted(date: .abbreviated, time: .standard)) }
            if let t = m.exposureTime { row("Exposure", Self.exposure(t)) }
            if let f = m.fNumber { row("Aperture", "f/" + f.formatted(.number.precision(.fractionLength(0...1)))) }
            if let iso = m.iso { row("ISO", "\(iso)") }
            if let fl = m.focalLength { row("Focal length", fl.formatted(.number.precision(.fractionLength(0...1))) + " mm") }
        }
    }

    private func gpsSection(_ m: ImageMetadata) -> some View {
        Section {
            if let lat = m.latitude, let lon = m.longitude {
                row("Latitude", Self.degrees(lat, positive: "N", negative: "S"))
                row("Longitude", Self.degrees(lon, positive: "E", negative: "W"))
            }
            if let alt = m.altitude { row("Altitude", alt.formatted(.number.precision(.fractionLength(0...1))) + " m") }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
        } label: {
            Text(title, tableName: "Viewer")
        }
    }

    // MARK: Formatting

    static func exposure(_ seconds: Double) -> String {
        if seconds >= 1 { return seconds.formatted(.number.precision(.fractionLength(0...1))) + " s" }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    static func degrees(_ value: Double, positive: String, negative: String) -> String {
        abs(value).formatted(.number.precision(.fractionLength(5))) + "° " + (value < 0 ? negative : positive)
    }

    static func megapixels(_ count: Int) -> String {
        let mp = Double(count) / 1_000_000
        let exact = count.formatted()
        return mp >= 0.1 ? "\(mp.formatted(.number.precision(.fractionLength(1)))) MP (\(exact))" : exact
    }
}
