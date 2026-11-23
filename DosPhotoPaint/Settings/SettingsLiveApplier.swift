import AppKit

/// Applies settings that must take effect in already-open windows/documents, using the
/// Observation framework (no notifications). Installed once at launch.
@MainActor
final class SettingsLiveApplier {
    static let shared = SettingsLiveApplier()
    private var installed = false
    private var lastToolbarVisible: Bool?
    private var lastPalettePosition: ToolPalettePosition?

    func install() {
        guard !installed else { return }
        installed = true
        observeContinuously(self) { $0.apply() }
    }

    private func apply() {
        let settings = AppSettings.shared
        let toolbarVisible = settings.showToolbar
        let undoLevels = settings.paintUndoLevels
        for document in NSDocumentController.shared.documents {
            if document.undoManager?.levelsOfUndo != undoLevels { document.undoManager?.levelsOfUndo = undoLevels }
        }
        let toolbarChanged = lastToolbarVisible != toolbarVisible
        lastToolbarVisible = toolbarVisible
        let palettePosition = settings.paintToolPalettePosition
        let paletteChanged = lastPalettePosition != nil && lastPalettePosition != palettePosition
        lastPalettePosition = palettePosition
        for window in NSApp.windows {
            guard let controller = window.windowController as? MainWindowController else { continue }
            controller.applyViewSettings()  // reads the display settings, so they are tracked
            if toolbarChanged { controller.updateToolbarVisibility() }
            if paletteChanged { controller.applyPaletteLayout(animated: false) }
        }
    }
}
