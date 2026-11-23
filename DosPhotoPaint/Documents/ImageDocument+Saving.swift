import AppKit
import UniformTypeIdentifiers

/// Save panel customisation, save confirmations (flattening / lossy re-encode), export,
/// "Save as Project" and the close-confirmation setting.
extension ImageDocument {

    // MARK: - Save panel

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanelAccessory?.invalidate()
        // NSDocument has already installed its file-format popup as the accessory: wrap it.
        let accessory = SavePanelAccessory(panel: savePanel, base: savePanel.accessoryView,
                                           quality: AppSettings.shared.saveJPEGQuality)
        savePanelAccessory = accessory
        savePanel.accessoryView = accessory.view
        return true
    }

    // MARK: - Save with confirmation

    private enum Warning {
        case flatten(alsoLossyOverOriginal: Bool)
        case inPlace(lossy: Bool)
    }

    private enum Decision { case proceed, cancel, saveAsProject }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping @MainActor @Sendable ((any Error)?) -> Void) {
        // Autosave goes to NSDocument's recovery location as a project; nothing to ask there.
        switch saveOperation {
        case .saveOperation, .saveAsOperation, .saveToOperation: break
        default:
            super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
            return
        }

        // Quality chosen in the panel that produced `url` applies to this save only.
        let accessory = savePanelAccessory
        savePanelAccessory = nil
        accessory?.invalidate()
        if let accessory, accessory.belongs(to: url) { jpegQualityOverride = accessory.quality }

        let finish: @MainActor @Sendable ((any Error)?) -> Void = { [weak self] error in
            self?.jpegQualityOverride = nil
            completionHandler(error)
        }

        guard let warning = warning(for: url, typeName: typeName, operation: saveOperation) else {
            super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: finish)
            return
        }
        Task { @MainActor in
            switch await self.ask(warning) {
            case .proceed:
                if saveOperation != .saveToOperation, self.fileURL?.standardizedFileURL == url.standardizedFileURL { self.confirmedInPlaceOverwrite = true }
                super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: finish)
            case .cancel:
                finish(CocoaError(.userCancelled))
            case .saveAsProject:
                finish(CocoaError(.userCancelled))
                self.beginSaveAsProject()
            }
        }
    }

    private func warning(for url: URL, typeName: String, operation: NSDocument.SaveOperationType) -> Warning? {
        guard let type = UTType(typeName), !type.conforms(to: ImageTypes.project) else { return nil }
        let setting = AppSettings.shared.saveOverwriteConfirmation
        let target = url.standardizedFileURL
        let overwritesOriginal = fileURL?.standardizedFileURL == target && !confirmedInPlaceOverwrite
        var existingType: UTType?
        if overwritesOriginal {
            existingType = (try? target.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        }
        let lossyOverOriginal = overwritesOriginal && ImageTypes.isLossy(type)
            && (existingType.map(ImageTypes.isLossy) ?? false)

        // Exports are explicit flattened copies; only guard against clobbering the original.
        if operation != .saveToOperation, (canvas?.layers.count ?? 0) > 1 {
            return .flatten(alsoLossyOverOriginal: lossyOverOriginal)
        }
        if lossyOverOriginal { return .inPlace(lossy: true) }
        // "Always": also confirm replacing an existing original in place with a lossless re-encode.
        if setting == .always, overwritesOriginal, existingType != nil { return .inPlace(lossy: false) }
        return nil
    }

    private func ask(_ warning: Warning) async -> Decision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch warning {
        case .flatten(let lossy):
            alert.messageText = String(localized: "Layers will be flattened", table: "Documents")
            var info = String(localized: "This image format stores a single layer. Save as a project (.dpp) to keep the layers.", table: "Documents")
            if lossy {
                info += "\n\n" + String(localized: "The original file will also be re-encoded with lossy compression.", table: "Documents")
            }
            alert.informativeText = info
            alert.addButton(withTitle: String(localized: "Save Flattened", table: "Documents"))
            alert.addButton(withTitle: String(localized: "Save as Project…", table: "Documents"))
            alert.addButton(withTitle: String(localized: "Cancel", table: "Documents"))
        case .inPlace(let lossy):
            alert.messageText = lossy
                ? String(localized: "Replace the original with a re-compressed image?", table: "Documents")
                : String(localized: "Replace the original image?", table: "Documents")
            alert.informativeText = lossy
                ? String(localized: "Saving re-encodes this JPEG/HEIC image, which slightly reduces quality. Use Save As to keep the original.", table: "Documents")
                : String(localized: "The original file will be overwritten. Use Save As to keep the original.", table: "Documents")
            alert.addButton(withTitle: String(localized: "Replace", table: "Documents"))
            alert.addButton(withTitle: String(localized: "Cancel", table: "Documents"))
        }
        let response: NSApplication.ModalResponse
        if let window = windowForSheet {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        switch (warning, response) {
        case (_, .alertFirstButtonReturn): return .proceed
        case (.flatten, .alertSecondButtonReturn): return .saveAsProject
        default: return .cancel
        }
    }

    // MARK: - Save as Project

    /// Save As with the project (.dpp) format preselected (layers are kept).
    func beginSaveAsProject() {
        let previousType = fileType
        fileType = ImageTypes.project.identifier
        let helper = SaveAsHelper { [weak self] saved in
            guard let self else { return }
            if !saved { self.fileType = previousType }
            self.saveHelper = nil
        }
        saveHelper = helper
        runModalSavePanel(for: .saveAsOperation, delegate: helper,
                          didSave: #selector(SaveAsHelper.document(_:didSave:contextInfo:)), contextInfo: nil)
    }

    // MARK: - Export

    /// Exports a flattened copy in a chosen format. The document keeps its file URL, type and
    /// edited state (`.saveToOperation`).
    func beginExport(in window: NSWindow?) {
        let formats = ImageTypes.writable
        guard !formats.isEmpty else { return }
        let initial = contentType.flatMap { t in formats.first { t.conforms(to: $0) } }
            ?? formats.first { $0 == UTType(DocumentController.shared.defaultType ?? "") } ?? formats[0]

        let panel = NSSavePanel()
        panel.title = String(localized: "Export", table: "Documents")
        panel.prompt = String(localized: "Export", table: "Documents")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [initial]
        panel.allowsOtherFileTypes = false
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? displayName ?? "Untitled"
        panel.nameFieldStringValue = base + "." + (initial.preferredFilenameExtension ?? "png")
        if let dir = fileURL?.deletingLastPathComponent() { panel.directoryURL = dir }
        let accessory = SavePanelAccessory(panel: panel, base: nil, quality: AppSettings.shared.saveJPEGQuality,
                                           formats: formats, selected: initial)
        panel.accessoryView = accessory.view

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url,
                  let type = accessory.selectedType ?? UTType(filenameExtension: url.pathExtension) else {
                accessory.invalidate()
                return
            }
            self.savePanelAccessory = accessory  // consumed by save(to:…): quality + original-overwrite check
            self.save(to: url, ofType: type.identifier, for: .saveToOperation) { [weak self] error in
                guard let self else { return }
                guard let error else {
                    // Exporting over the document's own file must not look like a foreign change later.
                    if let own = self.fileURL, own.standardizedFileURL == url.standardizedFileURL {
                        self.fileModificationDate = (try? own.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    }
                    return
                }
                if (error as NSError).code == NSUserCancelledError, (error as NSError).domain == NSCocoaErrorDomain { return }
                if let window = window ?? self.windowForSheet {
                    self.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
                } else {
                    self.presentError(error)
                }
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    // MARK: - Close confirmation setting

    /// With "confirm unsaved changes on close" off, closing an edited document discards the
    /// changes without the save sheet.
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        guard !AppSettings.shared.confirmUnsavedOnClose, isDocumentEdited else {
            super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
            return
        }
        Self.invokeShouldClose(delegate, selector: shouldCloseSelector, document: self, shouldClose: true, contextInfo: contextInfo)
    }

    /// Calls `-document:shouldClose:contextInfo:` the way AppKit would (a selector-based callback).
    static func invokeShouldClose(_ delegate: Any, selector: Selector?, document: NSDocument,
                                  shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard let selector, let target = delegate as? NSObject, target.responds(to: selector) else { return }
        typealias Callback = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        let imp = target.method(for: selector)
        let call = unsafeBitCast(imp, to: Callback.self)
        call(target, selector, document, shouldClose, contextInfo)
    }
}

/// Receives `-document:didSave:contextInfo:` from `runModalSavePanel`.
private final class SaveAsHelper: NSObject {
    private let completion: (Bool) -> Void
    init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }

    @objc func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        completion(didSave)
    }
}
