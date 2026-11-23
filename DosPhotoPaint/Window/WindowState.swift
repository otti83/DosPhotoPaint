import AppKit
import Observation

enum WindowMode: String, Sendable {
    case photo, paint
}

/// Per-window UI state shared by the AppKit controllers and SwiftUI panels.
@Observable
final class WindowState {
    var mode: WindowMode = .photo
    /// Scroll-view magnification (1 = 100 %).
    var zoom: Double = 1
    /// Image pixel size currently shown (nil while nothing is loaded).
    var imageSize: CGSize?
    /// Incremented whenever the window shows a different editable canvas (materialized, replaced, document
    /// switched), so SwiftUI panels that read `controller.canvas` refresh even if the image size is unchanged.
    var canvasGeneration = 0
    /// Pointer location in image pixels (nil when outside the canvas).
    var cursorPixel: CGPoint?
    /// Size of the active selection in pixels.
    var selectionSize: CGSize?
    /// 1-based position in the browsing session and total (Photo Mode).
    var sessionPosition: (index: Int, count: Int)?
    /// Transient status message (loading, errors…).
    var statusMessage: String?
    var isLoading = false
    var isSlideshowRunning = false
    var isSlideshowPaused = false
    /// True when the document has unsaved changes (mirrors NSDocument.isDocumentEdited).
    var isEdited = false
    /// Whether side panels are visible in Paint Mode (user can collapse them).
    var showsToolPalette = true
    var showsInspector = true
    /// Image info panel visible (Photo Mode).
    var showsImageInfo = false
    /// Image browser (list / tiles of the folder) shown over the canvas (Photo Mode).
    var showsImageBrowser = false

    /// Marks the window busy with a long-running edit. Returns false (and changes nothing) if one is already running.
    func beginBusy(_ message: String) -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        statusMessage = message
        return true
    }

    func endBusy() {
        isLoading = false
        statusMessage = nil
    }
}
