import AppKit
import SwiftUI

/// Floating utility panel showing `ImageInfoView` for the window's current image.
/// It never takes over keyboard focus from the canvas unless text in it is clicked.
final class ImageInfoPanelController: NSObject, NSWindowDelegate {
    unowned let controller: MainWindowController
    let model = ImageInfoModel()
    private var panel: NSPanel?
    private var loadTask: Task<Void, Never>?

    init(controller: MainWindowController) {
        self.controller = controller
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        controller.state.showsImageInfo = true
        refresh()
        panel.orderFront(nil)
    }

    func close() {
        loadTask?.cancel()
        panel?.orderOut(nil)
        controller.state.showsImageInfo = false
    }

    /// Re-reads the metadata for the current document (no-op while hidden).
    func refresh() {
        guard isVisible else { return }
        loadTask?.cancel()
        let doc = controller.imageDocument
        model.isEdited = doc?.isDocumentEdited ?? false
        model.fallbackSize = controller.state.imageSize
        guard let url = doc?.fileURL else {
            model.metadata = nil
            model.isLoading = false
            return
        }
        model.isLoading = model.metadata?.url != url
        loadTask = Task { [weak self] in
            let metadata = await Task.detached(priority: .userInitiated) { ImageMetadata.read(from: url) }.value
            guard let self, !Task.isCancelled else { return }
            self.model.metadata = metadata
            self.model.isLoading = false
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.title = String(localized: "Image Info", table: "Viewer")
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior.insert(.fullScreenAuxiliary)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ImageInfoView(model: model))
        if let frame = controller.window?.frame {
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width - 16, y: frame.maxY - 60))
        }
        return panel
    }

    func windowWillClose(_ notification: Notification) {
        loadTask?.cancel()
        controller.state.showsImageInfo = false
    }
}
