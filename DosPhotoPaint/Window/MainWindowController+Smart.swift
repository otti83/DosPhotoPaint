import AppKit

/// Smart Edit commands (Image ▸ Smart Edit, the Paint toolbar and the tool ribbon): subject
/// cut-out with Vision and Core Image auto enhance. Paint Mode only; each is one undo step.
extension MainWindowController {

    @objc func removeBackground(_ sender: Any?) {
        runSmartEdit(String(localized: "Remove Background", table: "Paint"),
                     busy: String(localized: "Finding the subject…", table: "Paint")) { model, name in
            try await model.removeBackground(actionName: name)
        }
    }

    @objc func copySubjectToNewLayer(_ sender: Any?) {
        runSmartEdit(String(localized: "Copy Subject to New Layer", table: "Paint"),
                     busy: String(localized: "Finding the subject…", table: "Paint")) { model, name in
            try await model.copySubjectToNewLayer(name: String(localized: "Subject", table: "Paint"), actionName: name)
        }
    }

    @objc func autoEnhance(_ sender: Any?) {
        runSmartEdit(String(localized: "Auto Enhance", table: "Paint"),
                     busy: String(localized: "Enhancing…", table: "Paint")) { model, name in
            try await model.autoEnhanceActiveLayer(actionName: name)
        }
    }

    /// Whether a Smart Edit command can run now (also used by the SwiftUI ribbon menu, which
    /// has no AppKit validation).
    var canRunSmartEdit: Bool {
        state.mode == .paint && canvas != nil && !state.isLoading && !viewer.ui.isComparing
    }

    private func runSmartEdit(_ actionName: String, busy: String,
                              _ body: @escaping @MainActor (CanvasModel, String) async throws -> Void) {
        guard canRunSmartEdit, let doc = imageDocument, let model = canvas else { NSSound.beep(); return }
        canvasView.cancelToolGesture()
        // Tool state that refers to the current pixels must be settled first (as for other whole-image edits).
        if let text = activeTool as? TextTool { text.commit(force: true) }
        if let crop = cropTool, let ctx = toolContext { crop.discard(context: ctx) }
        guard state.beginBusy(busy) else { return }
        Task {
            defer { state.endBusy() }
            do {
                try await body(model, actionName)
            } catch {
                guard imageDocument === doc else { return }
                presentSmartEditError(error, actionName: actionName)
            }
        }
    }

    private func presentSmartEditError(_ error: Error, actionName: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = actionName
        switch error {
        case SmartImageOps.Failure.noSubject:
            alert.informativeText = String(localized: "No subject was found in this image.", table: "Paint")
        case CanvasModel.EditError.canvasChanged:
            alert.informativeText = String(localized: "The image changed while it was being processed. Please try again.", table: "Paint")
        default:
            alert.informativeText = String(localized: "The edit could not be completed (not enough memory?).", table: "Paint")
        }
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
