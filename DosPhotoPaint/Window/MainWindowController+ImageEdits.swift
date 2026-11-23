import AppKit
import SwiftUI

/// Rotate, flip, resize image and canvas size. Work in both modes: Photo Mode materializes the
/// editable canvas first (off the main thread), so the edit is a real, undoable document edit.
extension MainWindowController {

    @objc func rotateLeft(_ sender: Any?) { run(.rotateLeft, String(localized: "Rotate Left", table: "Paint"), busy: String(localized: "Rotating…", table: "Paint")) }
    @objc func rotateRight(_ sender: Any?) { run(.rotateRight, String(localized: "Rotate Right", table: "Paint"), busy: String(localized: "Rotating…", table: "Paint")) }
    @objc func rotate180(_ sender: Any?) { run(.rotate180, String(localized: "Rotate 180°", table: "Paint"), busy: String(localized: "Rotating…", table: "Paint")) }
    @objc func flipHorizontal(_ sender: Any?) { run(.flipHorizontal, String(localized: "Flip Horizontal", table: "Paint"), busy: String(localized: "Flipping…", table: "Paint")) }
    @objc func flipVertical(_ sender: Any?) { run(.flipVertical, String(localized: "Flip Vertical", table: "Paint"), busy: String(localized: "Flipping…", table: "Paint")) }

    @objc func resizeImage(_ sender: Any?) {
        guard let size = state.imageSize else { return }
        presentSheet { dismiss in
            ResizeImageSheet(original: size, onApply: { [weak self] params in
                dismiss()
                self?.run(.resize(width: params.width, height: params.height, interpolation: params.interpolation),
                          String(localized: "Resize Image", table: "Paint"), busy: String(localized: "Resizing…", table: "Paint"))
            }, onCancel: dismiss)
        }
    }

    @objc func resizeCanvas(_ sender: Any?) {
        guard let size = state.imageSize else { return }
        presentSheet { dismiss in
            CanvasSizeSheet(original: size, onApply: { [weak self] params in
                dismiss()
                guard let self else { return }
                let offset = ImageResampler.anchoredOffset(
                    oldWidth: Int(size.width), oldHeight: Int(size.height),
                    newWidth: params.width, newHeight: params.height, column: params.column, row: params.row)
                let fill = params.fillWithSecondary ? self.toolSettings.secondaryColor.cgColor : nil
                self.run(.canvasSize(width: params.width, height: params.height, offsetX: offset.x, offsetY: offset.y),
                         String(localized: "Canvas Size", table: "Paint"), background: fill, busy: String(localized: "Changing canvas size…", table: "Paint"))
            }, onCancel: dismiss)
        }
    }

    // MARK: - Running an edit

    private func run(_ edit: ImageEdit, _ actionName: String, background: CGColor? = nil, busy: String) {
        Task { await perform(edit, actionName: actionName, background: background, busy: busy) }
    }

    private func perform(_ edit: ImageEdit, actionName: String, background: CGColor?, busy: String) async {
        guard let doc = imageDocument, !state.isLoading else { return }
        canvasView.cancelToolGesture()
        // Tool state in pixel coordinates of the old geometry must not survive the edit.
        if let text = activeTool as? TextTool { text.commit(force: true) }
        if let crop = cropTool, let ctx = toolContext { crop.discard(context: ctx) }
        state.isLoading = true
        state.statusMessage = busy
        defer {
            state.isLoading = false
            state.statusMessage = nil
        }
        do {
            let model = try await doc.materializeCanvas()
            guard imageDocument === doc else { return }
            let before = model.size
            try await model.apply(edit, actionName: actionName, background: background)
            if model.size != before, state.mode == .photo { applyInitialZoom() }
        } catch {
            guard imageDocument === doc, let window else { return }
            let alert = NSAlert()
            alert.messageText = actionName
            switch error {
            case CanvasModel.EditError.invalidSize:
                alert.informativeText = String(localized: "The resulting image size is not supported.", table: "Paint")
            case CanvasModel.EditError.canvasChanged:
                alert.informativeText = String(localized: "The image changed while it was being processed. Please try again.", table: "Paint")
            default:
                alert.informativeText = String(localized: "The edit could not be completed (not enough memory?).", table: "Paint")
            }
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    // MARK: - Sheets

    /// Presents `content` as a sheet; `dismiss` ends it.
    func presentSheet<Content: View>(_ content: (_ dismiss: @escaping () -> Void) -> Content) {
        guard let window else { return }
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        let sheet = NSWindow(contentViewController: host)
        sheet.styleMask = [.titled]
        host.rootView = AnyView(content { [weak window, weak sheet] in
            if let sheet { window?.endSheet(sheet) }
        })
        window.beginSheet(sheet)
    }
}
