import AppKit
import UniformTypeIdentifiers

/// Drag & drop onto the canvas.
///
/// - Photo Mode: dropped image files open (one file → shown in this window; several → one session).
/// - Paint Mode: the user chooses between opening as new image(s) and inserting into the canvas
///   (Option held while dropping inserts directly).
enum DropHandling {
    static func imageURLs(_ info: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ([ImageTypes.project] + ImageTypes.readable).map(\.identifier),
        ]
        return (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
    }

    static func hasRawImage(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.availableType(from: [.png, .tiff]) != nil
    }

    static func draggingOperation(_ info: NSDraggingInfo, controller: MainWindowController) -> NSDragOperation {
        if info.draggingSource as? CanvasView === controller.canvasView { return [] }
        if !imageURLs(info).isEmpty || hasRawImage(info) { return .copy }
        return []
    }

    static func performDrop(_ info: NSDraggingInfo, controller: MainWindowController) -> Bool {
        let urls = imageURLs(info)
        if controller.state.mode == .photo || controller.canvas == nil {
            guard !urls.isEmpty else { return false }
            if urls.count == 1, controller.imageDocument != nil,
               !(UTType(filenameExtension: urls[0].pathExtension)?.conforms(to: ImageTypes.project) ?? false) {
                // The session is reset only once the unsaved-changes prompt (if any) was not cancelled.
                Task { await controller.navigate(to: urls[0], resettingSession: true) }
            } else {
                DocumentController.shared.openForViewing(urls)
            }
            return true
        }
        // Paint Mode
        let insert = { () -> Bool in
            let image: CGImage? = urls.first.flatMap { try? ImageLoader.loadFullImage(url: $0).image }
                ?? ClipboardImage.readImage(info.draggingPasteboard)
            guard let image else { return false }
            let drop = controller.canvasView.convert(info.draggingLocation, from: nil)
            return controller.insertImageAsFloating(image, centeredAt: drop)
        }
        if NSEvent.modifierFlags.contains(.option) || urls.isEmpty { return insert() }
        guard let window = controller.window else { return false }
        let alert = NSAlert()
        alert.messageText = String(localized: "Drop Image", table: "Window")
        alert.informativeText = String(localized: "Do you want to insert the image into the current canvas or open it as a new image?", table: "Window")
        alert.addButton(withTitle: String(localized: "Insert into Canvas", table: "Window"))
        alert.addButton(withTitle: String(localized: "Open as New Image", table: "Window"))
        alert.addButton(withTitle: String(localized: "Cancel", table: "Window"))
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: _ = insert()
            case .alertSecondButtonReturn: DocumentController.shared.openForViewing(urls)
            default: break
            }
        }
        return true
    }
}
