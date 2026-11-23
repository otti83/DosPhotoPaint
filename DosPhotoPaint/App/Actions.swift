import AppKit

/// Custom responder-chain actions used by menus and toolbars.
///
/// Implemented by `MainWindowController` (and its extensions) or by the app delegate.
/// Every selector declared here must be implemented and validated somewhere — menus are built
/// from this list and an unimplemented action would show as a permanently disabled item.
@objc protocol AppActions {
    // App
    @objc optional func showSettings(_ sender: Any?)
    @objc optional func showKeyboardShortcuts(_ sender: Any?)
    @objc optional func showHelp(_ sender: Any?)

    // File
    @objc optional func newFromClipboard(_ sender: Any?)
    @objc optional func openInNewWindow(_ sender: Any?)
    @objc optional func exportImage(_ sender: Any?)
    @objc optional func saveAsProject(_ sender: Any?)
    @objc optional func revealInFinder(_ sender: Any?)
    @objc optional func copyImagePath(_ sender: Any?)
    @objc optional func grantFolderAccess(_ sender: Any?)
    @objc optional func shareImage(_ sender: Any?)

    // Edit
    @objc optional func pasteAsNewImage(_ sender: Any?)
    @objc optional func pasteAsNewLayer(_ sender: Any?)
    @objc optional func deselectAll(_ sender: Any?)

    // View / mode
    @objc optional func togglePaintMode(_ sender: Any?)
    @objc optional func zoomIn(_ sender: Any?)
    @objc optional func zoomOut(_ sender: Any?)
    @objc optional func zoomToFit(_ sender: Any?)
    @objc optional func zoomToFitWidth(_ sender: Any?)
    @objc optional func zoomToFitHeight(_ sender: Any?)
    @objc optional func zoomToActualSize(_ sender: Any?)
    @objc optional func zoomToActualPixels(_ sender: Any?)
    @objc optional func setCustomZoom(_ sender: Any?)
    @objc optional func toggleStatusBar(_ sender: Any?)
    @objc optional func toggleToolbar(_ sender: Any?)
    @objc optional func toggleToolPalette(_ sender: Any?)
    @objc optional func toggleInspector(_ sender: Any?)
    @objc optional func toggleCheckerboard(_ sender: Any?)
    /// sender.tag = index in `ViewerBackgroundSetting.allCases`
    @objc optional func setViewerBackground(_ sender: Any?)
    @objc optional func toggleImageInfo(_ sender: Any?)
    @objc optional func startSlideshow(_ sender: Any?)
    @objc optional func toggleImageBrowser(_ sender: Any?)
    @objc optional func compareWithOriginal(_ sender: Any?)

    // Navigation
    @objc optional func showPreviousImage(_ sender: Any?)
    @objc optional func showNextImage(_ sender: Any?)
    @objc optional func showFirstImage(_ sender: Any?)
    @objc optional func showLastImage(_ sender: Any?)
    /// sender.tag = index in `ImageSortOrder.allCases`
    @objc optional func setSortOrder(_ sender: Any?)

    // Image
    @objc optional func rotateLeft(_ sender: Any?)
    @objc optional func rotateRight(_ sender: Any?)
    @objc optional func rotate180(_ sender: Any?)
    @objc optional func flipHorizontal(_ sender: Any?)
    @objc optional func flipVertical(_ sender: Any?)
    @objc optional func resizeImage(_ sender: Any?)
    @objc optional func resizeCanvas(_ sender: Any?)
    @objc optional func cropToSelection(_ sender: Any?)

    // Smart Edit (Vision / Core Image, on device)
    @objc optional func removeBackground(_ sender: Any?)
    @objc optional func copySubjectToNewLayer(_ sender: Any?)
    @objc optional func autoEnhance(_ sender: Any?)

    // Layers
    @objc optional func newLayer(_ sender: Any?)
    @objc optional func duplicateLayer(_ sender: Any?)
    @objc optional func deleteLayer(_ sender: Any?)
    @objc optional func mergeLayerDown(_ sender: Any?)
    @objc optional func flattenImage(_ sender: Any?)
    @objc optional func moveLayerUp(_ sender: Any?)
    @objc optional func moveLayerDown(_ sender: Any?)

    // Tools
    /// sender.tag = index in `ToolKind.allCases`
    @objc optional func selectTool(_ sender: Any?)
    @objc optional func swapColors(_ sender: Any?)
    @objc optional func showColorPicker(_ sender: Any?)
    @objc optional func increaseToolSize(_ sender: Any?)
    @objc optional func decreaseToolSize(_ sender: Any?)
}
