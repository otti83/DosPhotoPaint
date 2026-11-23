import AppKit

/// File-menu actions implemented by the documents module. Validation lives in
/// `MainWindowController+Actions.swift` (`isEnabled`).
extension MainWindowController {

    /// ⇧⌘E — flattened copy in a chosen format; the document's file and edited state are untouched.
    @objc func exportImage(_ sender: Any?) {
        imageDocument?.beginExport(in: window)
    }

    /// Save As with the project (.dpp) format preselected.
    @objc func saveAsProject(_ sender: Any?) {
        guard let doc = imageDocument else { return }
        // Unedited, unmaterialized images are decoded on demand when written.
        doc.beginSaveAsProject()
    }
}
