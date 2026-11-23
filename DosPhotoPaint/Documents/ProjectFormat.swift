import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// DosPhotoPaint project (`.dpp`) — a document package:
///
/// ```
/// Name.dpp/
///   manifest.json        versioned metadata (ProjectManifest)
///   colorProfile.icc     ICC profile of the canvas colour space (optional; sRGB if absent)
///   layers/<uuid>.png    one PNG per layer (RGBA, full canvas size)
///   preview.png          flattened composite (for previews / recovery)
/// ```
///
/// Readers must ignore unknown manifest keys and reject a `formatVersion` newer than
/// `ProjectFormat.currentVersion`.
enum ProjectFormat {
    static let currentVersion = 1
    static let manifestName = "manifest.json"
    static let profileName = "colorProfile.icc"
    static let layersDirectory = "layers"
    static let previewName = "preview.png"

    struct Manifest: Codable, Equatable {
        var formatVersion: Int
        var generator: String
        var width: Int
        var height: Int
        var activeLayerID: UUID?
        /// Bottom → top.
        var layers: [LayerEntry]
    }

    struct LayerEntry: Codable, Equatable {
        var id: UUID
        var name: String
        var isVisible: Bool
        var opacity: Double
        var file: String
    }

    enum FormatError: LocalizedError {
        case missingManifest
        case newerVersion(Int)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .missingManifest:
                String(localized: "The project file is damaged (manifest missing).", table: "Documents")
            case .newerVersion(let v):
                String(localized: "This project was created by a newer version of DosPhotoPaint (format \(v)).", table: "Documents")
            case .corrupt(let detail):
                String(localized: "The project file is damaged (\(detail)).", table: "Documents")
            }
        }
    }

    // MARK: Write

    static func fileWrapper(for canvas: CanvasModel) throws -> FileWrapper {
        var entries: [LayerEntry] = []
        var layerFiles: [String: FileWrapper] = [:]
        for layer in canvas.layers {
            guard let image = layer.buffer.copyImage() else { throw FormatError.corrupt("layer \(layer.name)") }
            let file = "\(layer.id.uuidString).png"
            layerFiles[file] = FileWrapper(regularFileWithContents: try ImageEncoder.encode(image, as: .png, options: EncodeOptions(keepMetadata: false)))
            entries.append(LayerEntry(id: layer.id, name: layer.name, isVisible: layer.isVisible, opacity: layer.opacity, file: "\(layersDirectory)/\(file)"))
        }
        let manifest = Manifest(
            formatVersion: currentVersion,
            generator: "DosPhotoPaint \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")",
            width: canvas.width, height: canvas.height,
            activeLayerID: canvas.activeLayerID, layers: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var children: [String: FileWrapper] = [
            manifestName: FileWrapper(regularFileWithContents: try encoder.encode(manifest)),
            layersDirectory: FileWrapper(directoryWithFileWrappers: layerFiles),
        ]
        if let icc = canvas.colorSpace.copyICCData() as Data? {
            children[profileName] = FileWrapper(regularFileWithContents: icc)
        }
        if let preview = canvas.flattenedImage() {
            children[previewName] = FileWrapper(regularFileWithContents: try ImageEncoder.encode(preview, as: .png, options: EncodeOptions(keepMetadata: false)))
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    // MARK: Read

    static func readCanvas(from wrapper: FileWrapper) throws -> CanvasModel {
        guard wrapper.isDirectory, let files = wrapper.fileWrappers,
              let manifestData = files[manifestName]?.regularFileContents else { throw FormatError.missingManifest }
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: manifestData) }
        catch { throw FormatError.corrupt("manifest") }
        guard manifest.formatVersion <= currentVersion else { throw FormatError.newerVersion(manifest.formatVersion) }
        guard manifest.width > 0, manifest.height > 0, !manifest.layers.isEmpty,
              manifest.width * manifest.height <= ImageLoader.maxEditablePixels else { throw FormatError.corrupt("size") }
        guard Set(manifest.layers.map(\.id)).count == manifest.layers.count else { throw FormatError.corrupt("duplicate layer id") }

        let space = files[profileName]?.regularFileContents.flatMap { CGColorSpace(iccData: $0 as CFData) }
            .flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!

        var layers: [Layer] = []
        for entry in manifest.layers {
            let parts = entry.file.split(separator: "/").map(String.init)
            var node: FileWrapper? = wrapper
            for p in parts { node = node?.fileWrappers?[p] }
            guard let data = node?.regularFileContents,
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                  image.width == manifest.width, image.height == manifest.height,
                  let buffer = RasterBuffer(width: manifest.width, height: manifest.height, colorSpace: space)
            else { throw FormatError.corrupt("layer “\(entry.name)”") }
            buffer.replace(buffer.bounds, with: image)
            layers.append(Layer(id: entry.id, name: entry.name, buffer: buffer, isVisible: entry.isVisible,
                                opacity: entry.opacity.isFinite ? entry.opacity : 1))
        }
        guard let canvas = CanvasModel(width: manifest.width, height: manifest.height, colorSpace: space,
                                       layers: layers, activeLayerID: manifest.activeLayerID)
        else { throw FormatError.corrupt("canvas") }
        return canvas
    }
}
