import AppKit

/// Selection and crop actions (Edit ▸ Select All / Deselect / Delete, Image ▸ Crop to Selection).
extension MainWindowController {

    @objc override func selectAll(_ sender: Any?) {
        guard state.mode == .paint, let canvas else { return }
        canvas.commitFloatingIfNeeded()
        if toolSettings.tool != .rectangleSelect && toolSettings.tool != .lassoSelect { activateTool(.rectangleSelect) }
        canvas.setSelection(.rect(canvas.bounds), actionName: String(localized: "Select All", table: "Paint"))
    }

    @objc func deselectAll(_ sender: Any?) {
        guard let canvas else { return }
        canvas.commitFloatingIfNeeded()
        guard canvas.selection != nil else { return }
        canvas.setSelection(nil, actionName: String(localized: "Deselect", table: "Paint"))
    }

    /// Clears the selection contents to transparent (one undo step). On the background layer this
    /// leaves transparent pixels rather than the secondary colour.
    @objc func delete(_ sender: Any?) {
        guard state.mode == .paint, let canvas, !canvas.deleteSelectionContents(actionName: String(localized: "Delete", table: "Paint")) else { return }
        NSSound.beep()
    }

    /// Crops every layer to the bounding box of the selection. For free-form selections the
    /// bounding box is used; pixels outside the path but inside the box are kept.
    @objc func cropToSelection(_ sender: Any?) {
        guard state.mode == .paint, let canvas else { return }
        canvas.commitFloatingIfNeeded()
        guard !state.isLoading, let sel = canvas.selection, let rect = canvas.cropRect(for: sel.bounds) else { NSSound.beep(); return }
        let finish = { [weak self] (ok: Bool) in
            guard let self else { return }
            if ok {
                self.state.imageSize = canvas.size
                self.state.selectionSize = nil
            } else {
                NSSound.beep()
            }
        }
        if canvas.prefersOffloading {
            runBusy(String(localized: "Cropping…", table: "Paint"), then: finish) { await canvas.cropOffloaded(to: rect) }
        } else {
            finish(canvas.crop(to: rect))
        }
    }

    // MARK: Crop tool (inspector buttons)

    var cropTool: CropTool? { activeTool as? CropTool }

    @objc func applyCrop(_ sender: Any?) {
        guard let tool = cropTool, let ctx = toolContext, tool.apply(context: ctx) else { NSSound.beep(); return }
    }

    @objc func cancelCrop(_ sender: Any?) {
        guard let tool = cropTool, let ctx = toolContext else { return }
        tool.discard(context: ctx)
    }
}
