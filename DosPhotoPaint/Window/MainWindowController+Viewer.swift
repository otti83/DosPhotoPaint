import AppKit

/// Photo Mode viewer actions (the feature logic lives in `ViewerCoordinator`).
extension MainWindowController {
    @objc func toggleImageInfo(_ sender: Any?) {
        viewer.info.toggle()
    }

    @objc func startSlideshow(_ sender: Any?) {
        viewer.slideshow.toggle()
    }

    @objc func compareWithOriginal(_ sender: Any?) {
        viewer.toggleCompare()
    }

    /// Lets the user grant access to the folder of the current file (App Sandbox).
    @objc func grantFolderAccess(_ sender: Any?) {
        guard let window, let file = imageDocument?.fileURL ?? session.currentURL else { return }
        let folder = file.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = folder
        panel.prompt = String(localized: "Allow", table: "Viewer")
        panel.message = String(localized: "Allow access to this folder to browse its images", table: "Viewer")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let granted = url.standardizedFileURL.path
            let needed = folder.standardizedFileURL.path
            guard needed == granted || needed.hasPrefix(granted.hasSuffix("/") ? granted : granted + "/") else {
                self.state.statusMessage = String(localized: "The selected folder does not contain this image.", table: "Viewer")
                return
            }
            FolderAccess.remember(url)
            self.session.reloadFolder()
            self.viewer.reloadBrowser()
        }
    }

    // MARK: - Image browser

    @objc func toggleImageBrowser(_ sender: Any?) {
        guard state.mode == .photo, !state.isSlideshowRunning else { NSSound.beep(); return }
        state.showsImageBrowser.toggle()
    }

    func hideImageBrowser() {
        state.showsImageBrowser = false
    }

    /// Shows `url` (double-click in the browser) and returns to the image.
    func openFromBrowser(_ url: URL) {
        state.showsImageBrowser = false
        if ViewerCoordinator.isMissing(url) {
            viewer.skipMissing(url)
            viewer.reloadBrowser()
            return
        }
        Task { await navigate(to: url) }
    }
}
