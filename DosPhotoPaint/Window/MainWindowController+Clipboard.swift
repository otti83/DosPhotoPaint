import AppKit

/// Edit ▸ Copy / Cut / Paste / Paste as New Layer. Text editing is handled by `NSTextView`
/// before these are reached (it is earlier in the responder chain).
extension MainWindowController {

    @objc func copy(_ sender: Any?) {
        if let canvas {
            guard let image = clipboardImage(of: canvas) else { NSSound.beep(); return }
            ClipboardImage.write(image)
            return
        }
        // Photo Mode, image not materialized: decode the full image off the main thread.
        guard let url = imageDocument?.fileURL else { return }
        state.statusMessage = String(localized: "Copying image…", table: "Paint")
        Task { [weak self] in
            let decoded = try? await Task.detached(priority: .userInitiated) { try ImageLoader.loadFullImage(url: url) }.value
            self?.state.statusMessage = nil
            if let decoded { ClipboardImage.write(decoded.image) } else { NSSound.beep() }
        }
    }

    /// Copy, then clear the selection to transparent (one undo step).
    @objc func cut(_ sender: Any?) {
        guard state.mode == .paint, let canvas, canvas.selection != nil || canvas.floating != nil,
              let image = clipboardImage(of: canvas) else { NSSound.beep(); return }
        ClipboardImage.write(image)
        canvas.deleteSelectionContents(actionName: String(localized: "Cut", table: "Paint"))
    }

    @objc func paste(_ sender: Any?) { pasteFromClipboard(asNewLayer: false) }
    @objc func pasteAsNewLayer(_ sender: Any?) { pasteFromClipboard(asNewLayer: true) }

    /// Floating selection > selection of the active layer (Paint Mode) > whole composite.
    private func clipboardImage(of canvas: CanvasModel) -> CGImage? {
        if state.mode == .paint {
            if canvas.floating != nil { return canvas.renderedFloatingImage() }
            if let sel = canvas.selection, let layer = canvas.activeLayer { return canvas.selectionPixels(of: layer, in: sel)?.image }
        }
        return canvas.flattenedImage()
    }

    private func pasteFromClipboard(asNewLayer: Bool) {
        guard state.mode == .paint, let canvas, let image = ClipboardImage.readImage() else { NSSound.beep(); return }
        canvas.commitFloatingIfNeeded()
        guard image.width > canvas.width || image.height > canvas.height, let window else {
            finishPaste(image, into: canvas, asNewLayer: asNewLayer, expand: false)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "The image is larger than the canvas.", table: "Paint")
        alert.informativeText = String(localized: "Do you want to expand the canvas to fit the pasted image?", table: "Paint")
        alert.addButton(withTitle: String(localized: "Expand Canvas", table: "Paint"))
        alert.addButton(withTitle: String(localized: "Keep Canvas Size", table: "Paint"))
        alert.addButton(withTitle: String(localized: "Cancel", table: "Paint"))
        alert.beginSheetModal(for: window) { [weak self, weak canvas] response in
            guard let canvas else { return }
            switch response {
            case .alertFirstButtonReturn: self?.finishPaste(image, into: canvas, asNewLayer: asNewLayer, expand: true)
            case .alertSecondButtonReturn: self?.finishPaste(image, into: canvas, asNewLayer: asNewLayer, expand: false)
            default: break
            }
        }
    }

    /// `target` is the canvas the paste was requested for: the sheet is asynchronous, so the window
    /// may meanwhile show another document or have left Paint Mode.
    private func finishPaste(_ image: CGImage, into target: CanvasModel, asNewLayer: Bool, expand: Bool) {
        guard let canvas, canvas === target, state.mode == .paint else { return }
        if expand {
            canvas.expandCanvas(toWidth: image.width, height: image.height, background: toolSettings.secondaryColor.cgColor)
            state.imageSize = canvas.size
        }
        // The new layer and the paste are two undo steps (structural edit, then region merge).
        if asNewLayer, !canvas.addEmptyLayerAboveActive(name: String(localized: "Pasted Layer", table: "Paint")) { NSSound.beep(); return }
        insertImageAsFloating(image)
    }
}
