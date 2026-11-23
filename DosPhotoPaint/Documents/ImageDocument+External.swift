import AppKit

/// Reaction to the file changing or disappearing behind the document's back.
extension ImageDocument {

    /// NSFilePresenter callbacks arrive on an arbitrary queue.
    nonisolated override func presentedItemDidChange() {
        super.presentedItemDidChange()
        Task { @MainActor [weak self] in self?.handleExternalChange() }
    }

    /// Deleted/trashed while open: keep the document (it may hold the only copy) and say so.
    nonisolated override func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        completionHandler(nil)
        Task { @MainActor [weak self] in self?.handleExternalChange() }
    }

    private func handleExternalChange() {
        guard let url = fileURL, !isProject else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            // Keep the document (it may hold the only copy); tell the windows.
            reportedFileMissing = true
            post(missing: true)
            return
        }
        let recovered = reportedFileMissing
        reportedFileMissing = false

        // Edited documents keep their content; NSDocument warns about the conflict on save.
        guard !isDocumentEdited else { if recovered { post(missing: false) }; return }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != fileModificationDate else { if recovered { post(missing: false) }; return }

        // Only reload what is currently shown as a plain photo without history.
        let inPaintMode = windowControllers.contains { ($0 as? MainWindowController)?.state.mode == .paint }
        if inPaintMode { return }
        if canvas != nil, undoManager?.canUndo == true || undoManager?.canRedo == true { return }
        guard let info = try? ImageLoader.info(for: url) else { return }

        reloadFromDisk(info: info, modificationDate: modified)
        post(missing: false)
    }

    private func post(missing: Bool) {
        NotificationCenter.default.post(name: .imageDocumentFileDidChangeExternally, object: self,
                                        userInfo: [Self.fileMissingKey: missing])
    }
}
