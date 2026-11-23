import AppKit
import ImageIO
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted (object: ImageDocument) when the editable canvas became available.
    /// A `nil` canvas means the canvas was dropped (Revert to Saved / external change) and the
    /// file on disk must be shown again.
    static let imageDocumentCanvasDidMaterialize = Notification.Name("ImageDocumentCanvasDidMaterialize")
    /// Posted (object: ImageDocument) when the file changed on disk or disappeared; userInfo
    /// `ImageDocument.fileMissingKey` (Bool) tells which.
    static let imageDocumentFileDidChangeExternally = Notification.Name("ImageDocumentFileDidChangeExternally")
}

/// One image file, `.dpp` project or untitled canvas.
///
/// Viewing an image does **not** decode it at full resolution nor create a canvas:
/// `read(from:ofType:)` only reads header info. The editable `CanvasModel` is created on demand
/// by `materializeCanvas()` (Paint Mode / first edit). Nothing is ever written to disk except
/// through the explicit NSDocument save operations; autosave goes to a separate location.
final class ImageDocument: NSDocument {
    /// Header info of the file on disk (nil for untitled canvases).
    private(set) var sourceInfo: ImageSourceInfo?
    /// Metadata of the source image (EXIF/GPS/…), preserved on save according to settings.
    private(set) var sourceMetadata: CFDictionary?
    /// Editable canvas; nil until materialized.
    private(set) var canvas: CanvasModel?
    private var materializeTask: Task<CanvasModel, Error>?

    /// Set by DocumentController for documents opened through Finder/Open so the window
    /// controller knows the initial mode and browsing list.
    var openingContext: OpeningContext?

    static let fileMissingKey = "fileMissing"

    // Save-flow state (see ImageDocument+Saving.swift).
    /// Accessory of the save/export panel currently (or last) shown for this document.
    var savePanelAccessory: SavePanelAccessory?
    /// The user already confirmed re-encoding/overwriting the original file in place.
    var confirmedInPlaceOverwrite = false
    /// Keeps the "Save as Project" panel helper alive until the panel finishes.
    var saveHelper: AnyObject?
    /// A "file missing" status was reported to the windows (so recovery can clear it).
    var reportedFileMissing = false

    struct OpeningContext {
        var mode: WindowMode
        /// Files of an explicit multi-selection (nil → browse the file's folder).
        var sessionURLs: [URL]?
    }

    // MARK: - NSDocument configuration

    /// Never autosave in place: that would overwrite the original image.
    nonisolated override class var autosavesInPlace: Bool { false }
    override class var preservesVersions: Bool { false }
    override class var usesUbiquitousStorage: Bool { false }

    override class var writableTypes: [String] {
        [ImageTypes.project.identifier] + ImageTypes.writable.map(\.identifier)
    }

    override class func isNativeType(_ type: String) -> Bool {
        type == ImageTypes.project.identifier
    }

    /// Crash-recovery data always keeps the layers.
    nonisolated override var autosavingFileType: String? { ImageTypes.project.identifier }

    var contentType: UTType? { fileType.flatMap { UTType($0) } }
    var isProject: Bool { contentType?.conforms(to: ImageTypes.project) ?? false }
    var isMaterialized: Bool { canvas != nil }
    var isAnimated: Bool { sourceInfo?.isAnimated ?? false }

    /// Pixel size of what is shown (canvas if materialized, otherwise the file's upright size).
    var pixelSize: CGSize? {
        if let canvas { return canvas.size }
        if let info = sourceInfo { return CGSize(width: info.pixelWidth, height: info.pixelHeight) }
        return nil
    }

    // MARK: - New untitled canvas

    /// Untitled document: blank canvas from the Paint defaults.
    /// (NSDocumentController calls this as `-initWithType:error:`; never shows a dialog.)
    convenience init(type typeName: String) throws {
        try self.init(type: typeName, canvas: .settingsDefault())
    }

    /// Untitled document with an explicit size and background (File > New Canvas dialog).
    convenience init(type typeName: String, canvas spec: NewCanvasSpec, secondary: NSColor = ToolSettings.shared.secondaryColor) throws {
        self.init()
        fileType = typeName
        let spec = spec.clamped()
        guard let model = CanvasModel(width: spec.width, height: spec.height, background: spec.cgBackground(secondary: secondary)) else {
            throw CocoaError(.fileReadUnknown)
        }
        attach(model)
        openingContext = OpeningContext(mode: .paint, sessionURLs: nil)
    }

    /// Untitled document from an existing image (e.g. "New from Clipboard").
    convenience init(newFrom image: CGImage) throws {
        try self.init(type: DocumentController.shared.defaultType ?? UTType.png.identifier)
        guard let model = CanvasModel(image: image) else { throw CocoaError(.fileReadUnknown) }
        attach(model)
    }

    override init() {
        super.init()
    }

    // MARK: - Reading

    /// NSDocument declares reading nonisolated (for concurrent reading). This class does not opt
    /// into concurrent reading (`canConcurrentlyReadDocuments` is false), so AppKit always calls
    /// it on the main thread.
    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            try readOnMain(from: url, ofType: typeName)
        }
    }

    private func readOnMain(from url: URL, ofType typeName: String) throws {
        if UTType(typeName)?.conforms(to: ImageTypes.project) == true {
            let wrapper = try FileWrapper(url: url, options: .immediate)
            attach(try ProjectFormat.readCanvas(from: wrapper))
            sourceInfo = nil
            return
        }
        // Image: read header only. Pixels are decoded lazily (materializeCanvas).
        let isReread = sourceInfo != nil || canvas != nil
        sourceInfo = try ImageLoader.info(for: url)
        sourceMetadata = nil
        // Revert to Saved / external change: drop the edited canvas so the file is shown again.
        if isReread { ImageCache.shared.removeAll() }
        confirmedInPlaceOverwrite = false
        if canvas != nil {
            canvas = nil
            NotificationCenter.default.post(name: .imageDocumentCanvasDidMaterialize, object: self)
        }
    }

    /// External change of an unedited image: adopt the new header, drop the canvas and let the
    /// windows reload the file.
    func reloadFromDisk(info: ImageSourceInfo, modificationDate: Date?) {
        sourceInfo = info
        sourceMetadata = nil
        fileModificationDate = modificationDate
        ImageCache.shared.removeAll()
        canvas = nil
        NotificationCenter.default.post(name: .imageDocumentCanvasDidMaterialize, object: self)
    }

    /// Crash recovery / restoration: `url` is the original file, `contentsURL` the autosave (dpp).
    convenience init(for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String) throws {
        self.init()
        fileURL = urlOrNil
        // AppKit may pass the type of the autosaved contents (a project) rather than the type of
        // the original file. The document must keep describing the original file: otherwise Save
        // would write a package over an image path.
        let typeName = urlOrNil.flatMap { contentsURL == $0 ? nil : Self.originalFileType(of: $0) } ?? typeName
        fileType = typeName
        if contentsURL == urlOrNil {
            // Plain reopen of the file itself (no autosaved changes).
            try readOnMain(from: contentsURL, ofType: typeName)
            fileModificationDate = (try? contentsURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            openingContext = OpeningContext(mode: isProject ? .paint : .photo, sessionURLs: nil)
            return
        }
        // Autosaved contents are always a project package (see `autosavingFileType`).
        let wrapper = try FileWrapper(url: contentsURL, options: .immediate)
        attach(try ProjectFormat.readCanvas(from: wrapper))
        if let urlOrNil, !(UTType(typeName)?.conforms(to: ImageTypes.project) ?? false) {
            sourceInfo = try? ImageLoader.info(for: urlOrNil)
            sourceMetadata = (try? ImageLoader.makeSource(urlOrNil)).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) }
        }
        autosavedContentsFileURL = contentsURL
        if let urlOrNil {
            fileModificationDate = (try? urlOrNil.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        // Recovered content differs from the file on disk.
        if contentsURL != urlOrNil { updateChangeCount(.changeDone) }
        openingContext = OpeningContext(mode: .paint, sessionURLs: nil)
    }

    /// Type of an existing original file (project or readable image), nil if unknown.
    private static func originalFileType(of url: URL) -> String? {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension.lowercased())
        guard let type else { return nil }
        if type.conforms(to: ImageTypes.project) { return ImageTypes.project.identifier }
        return ImageTypes.isReadableImage(type) ? type.identifier : nil
    }

    // MARK: - Menu validation

    /// Save on an unedited document that has a file would only re-encode the original (lossy,
    /// drops metadata) for no reason, so it is disabled like in other editors.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSDocument.save(_:)), fileURL != nil, !isDocumentEdited { return false }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Materialization

    /// Returns the editable canvas, decoding the full-resolution image off the main thread if needed.
    @discardableResult
    func materializeCanvas() async throws -> CanvasModel {
        if let canvas { return canvas }
        if let task = materializeTask { return try await task.value }
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        let task = Task<CanvasModel, Error> {
            let decoded = try await Task.detached(priority: .userInitiated) {
                try ImageLoader.loadFullImage(url: url)
            }.value
            guard let model = CanvasModel(image: decoded.image) else {
                throw ImageLoadError.tooLarge(url, width: decoded.info.pixelWidth, height: decoded.info.pixelHeight)
            }
            self.sourceInfo = decoded.info
            self.sourceMetadata = decoded.properties
            return model
        }
        materializeTask = task
        defer { materializeTask = nil }
        let model = try await task.value
        if canvas == nil { attach(model) }
        return canvas!
    }

    private func attach(_ model: CanvasModel) {
        canvas = model
        model.undoManager = undoManager
        undoManager?.levelsOfUndo = AppSettings.shared.paintUndoLevels
        NotificationCenter.default.post(name: .imageDocumentCanvasDidMaterialize, object: self)
    }

    // MARK: - Writing

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        guard UTType(typeName)?.conforms(to: ImageTypes.project) == true else {
            return FileWrapper(regularFileWithContents: try data(ofType: typeName))
        }
        // An unmaterialized image saved as a project: adopt the decoded canvas so the document
        // keeps working once its file becomes the .dpp (the image loader cannot read it).
        if canvas == nil, let loaded = try currentCanvasForWriting() { attach(loaded) }
        guard let canvas else { throw CocoaError(.fileWriteUnknown) }
        return try ProjectFormat.fileWrapper(for: canvas)
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let type = UTType(typeName), ImageTypes.isWritable(type) else {
            throw ImageEncodeError.unsupportedType(typeName)
        }
        let s = AppSettings.shared
        var options = EncodeOptions()
        options.quality = jpegQualityOverride ?? s.saveJPEGQuality
        options.matteColor = s.saveJPEGBackground.rgbaColor
        options.metadata = sourceMetadata
        options.keepMetadata = s.saveKeepMetadata
        options.stripGPS = s.saveStripGPS
        options.convertToSRGB = s.saveColorProfile == .convertToSRGB

        let image: CGImage
        if let canvas = try currentCanvasForWriting() {
            canvas.commitFloatingIfNeeded()
            guard let flat = canvas.flattenedImage() else { throw ImageEncodeError.encodeFailed(typeName) }
            image = flat
        } else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try ImageEncoder.encode(image, as: type, options: options)
    }

    /// Canvas to write. For an unedited image (e.g. Save As/Duplicate from Photo Mode) the full
    /// image is decoded synchronously, since NSDocument writing is synchronous.
    private func currentCanvasForWriting() throws -> CanvasModel? {
        if let canvas { return canvas }
        guard let url = fileURL else { return nil }
        let decoded = try ImageLoader.loadFullImage(url: url)
        sourceMetadata = decoded.properties
        return CanvasModel(image: decoded.image)
    }

    /// JPEG/HEIC quality chosen in the save panel (overrides the default for this save only).
    var jpegQualityOverride: Double?

    // MARK: - Windows

    override func makeWindowControllers() {
        let mode = openingContext?.mode ?? (canvas != nil && fileURL == nil ? .paint : .photo)
        let wc = MainWindowController(initialMode: isProject ? .paint : mode, sessionURLs: openingContext?.sessionURLs)
        addWindowController(wc)
        openingContext = nil
    }
}

extension NSColor {
    /// Straight sRGB components.
    var rgbaColor: RGBAColor {
        let c = usingColorSpace(.sRGB) ?? .white
        return RGBAColor(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }
}
