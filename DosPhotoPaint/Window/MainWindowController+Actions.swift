import AppKit
import UniformTypeIdentifiers

/// View, navigation, mode and tool actions + the central menu/toolbar validation.
/// Image-editing actions live in other `MainWindowController+*.swift` extensions; their
/// validation rules are centralised here so every menu item has exactly one rule.
extension MainWindowController: NSMenuItemValidation, NSToolbarItemValidation {

    // MARK: Mode

    @objc func togglePaintMode(_ sender: Any?) {
        setMode(state.mode == .photo ? .paint : .photo)
    }

    // MARK: Zoom

    @objc func zoomIn(_ sender: Any?) { scrollView.setZoom(ZoomLevels.next(after: scrollView.magnification), anchor: zoomAnchor(), animated: true) }
    @objc func zoomOut(_ sender: Any?) { scrollView.setZoom(ZoomLevels.previous(before: scrollView.magnification), anchor: zoomAnchor(), animated: true) }
    @objc func zoomToFit(_ sender: Any?) { scrollView.zoomToFit(.window, allowUpscale: false) }
    @objc func zoomToFitWidth(_ sender: Any?) { scrollView.zoomToFit(.width, allowUpscale: true) }
    @objc func zoomToFitHeight(_ sender: Any?) { scrollView.zoomToFit(.height, allowUpscale: true) }
    @objc func zoomToActualSize(_ sender: Any?) { scrollView.setZoom(1, anchor: zoomAnchor()) }
    @objc func zoomToActualPixels(_ sender: Any?) {
        scrollView.setZoom(1 / (window?.backingScaleFactor ?? 2), anchor: zoomAnchor())
    }

    /// Keyboard zoom keeps the pointer position fixed when it is over the image.
    private func zoomAnchor() -> CGPoint? {
        guard settings.photoZoomAtCursor, let window else { return nil }
        let p = canvasView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return canvasView.visibleRect.contains(p) ? p : nil
    }

    /// Zoom requested by the status bar slider / percentage field: around the view centre.
    func setZoomFromStatusBar(_ zoom: CGFloat) {
        scrollView.setZoom(zoom)
    }

    /// The status bar must never keep keyboard focus after an interaction.
    func returnFocusToCanvas() {
        window?.makeFirstResponder(canvasView)
    }

    @objc func setCustomZoom(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Zoom To", table: "Window")
        alert.informativeText = String(localized: "Enter a zoom percentage (10–3200).", table: "Window")
        let field = NSTextField(string: String(format: "%.0f", scrollView.magnification * 100))
        field.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        field.formatter = {
            let f = NumberFormatter()
            f.minimum = 10; f.maximum = 3200; f.maximumFractionDigits = 1
            return f
        }()
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "OK", table: "Window"))
        alert.addButton(withTitle: String(localized: "Cancel", table: "Window"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let value = field.doubleValue
            guard value.isFinite, value > 0 else { return }
            self.scrollView.setZoom(CGFloat(value / 100))
        }
    }

    // MARK: Navigation

    @objc func showPreviousImage(_ sender: Any?) { step(-1) }
    @objc func showNextImage(_ sender: Any?) { step(1) }
    @objc func showFirstImage(_ sender: Any?) { showImage(at: 0) }
    @objc func showLastImage(_ sender: Any?) { showImage(at: session.urls.count - 1) }

    @objc func setSortOrder(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, ImageSortOrder.allCases.indices.contains(tag) else { return }
        settings.photoSortOrder = ImageSortOrder.allCases[tag]
        session.resort()
        updateSessionStatus()
    }

    // MARK: View toggles

    @objc func toggleStatusBar(_ sender: Any?) {
        settings.showStatusBar.toggle()
        NotificationCenter.default.post(name: .viewSettingsDidChange, object: nil)
    }

    /// Show/Hide Toolbar. Goes through the setting (not `NSWindow.toggleToolbarShown`) so the
    /// choice survives Photo/Paint toolbar swaps and applies to every window.
    @objc func toggleToolbar(_ sender: Any?) {
        settings.showToolbar.toggle()
        updateToolbarVisibility()
    }

    @objc func toggleToolPalette(_ sender: Any?) {
        state.showsToolPalette.toggle()
        applyModeUI(animated: true)
    }

    @objc func toggleInspector(_ sender: Any?) {
        state.showsInspector.toggle()
        applyModeUI(animated: true)
    }

    @objc func toggleCheckerboard(_ sender: Any?) {
        settings.photoCheckerboard.toggle()
        NotificationCenter.default.post(name: .viewSettingsDidChange, object: nil)
    }

    @objc func setViewerBackground(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, ViewerBackgroundSetting.allCases.indices.contains(tag) else { return }
        settings.photoBackground = ViewerBackgroundSetting.allCases[tag]
        NotificationCenter.default.post(name: .viewSettingsDidChange, object: nil)
    }

    // MARK: File helpers

    @objc func revealInFinder(_ sender: Any?) {
        guard let url = imageDocument?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func copyImagePath(_ sender: Any?) {
        guard let url = imageDocument?.fileURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }

    @objc func openInNewWindow(_ sender: Any?) {
        guard let doc = imageDocument else { return }
        let wc = MainWindowController(initialMode: state.mode == .paint && doc.isMaterialized ? .paint : .photo,
                                      sessionURLs: session.isExplicit ? session.urls : nil)
        doc.addWindowController(wc)
        if let frame = window?.frame { wc.window?.setFrameTopLeftPoint(NSPoint(x: frame.minX + 24, y: frame.maxY - 24)) }
        wc.showWindow(nil)
    }

    @objc func shareImage(_ sender: Any?) {
        let items = sharingItems()
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        let anchor = (sender as? NSView) ?? scrollView
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    // MARK: Tools

    @objc func selectTool(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag,
              ToolKind.allCases.indices.contains(tag) else { return }
        activateTool(ToolKind.allCases[tag])
    }

    @objc func swapColors(_ sender: Any?) { toolSettings.swapColors() }

    @objc func showColorPicker(_ sender: Any?) {
        ColorPanelBridge.shared.show(editing: .primary)
    }

    @objc func increaseToolSize(_ sender: Any?) { adjustToolSize(by: 1) }
    @objc func decreaseToolSize(_ sender: Any?) { adjustToolSize(by: -1) }

    // MARK: - Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        updateState(of: menuItem)
        return isEnabled(menuItem.action, tag: menuItem.tag)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        isEnabled(item.action, tag: item.tag)
    }

    /// Checkmarks / dynamic titles.
    private func updateState(of item: NSMenuItem) {
        guard let action = item.action else { return }
        func on(_ b: Bool) { item.state = b ? .on : .off }
        switch action {
        case #selector(togglePaintMode(_:)):
            item.title = state.mode == .photo ? String(localized: "Switch to Paint Mode", table: "Menu") : String(localized: "Switch to Photo Mode", table: "Menu")
        case #selector(toggleStatusBar(_:)): on(settings.showStatusBar)
        case #selector(toggleToolbar(_:)):
            item.title = settings.showToolbar ? String(localized: "Hide Toolbar", table: "Menu") : String(localized: "Show Toolbar", table: "Menu")
        case #selector(toggleToolPalette(_:)): on(state.mode == .paint && (usesTopToolRibbon ? !ribbonHost.isHidden : !paletteItem.isCollapsed))
        case #selector(toggleInspector(_:)): on(state.mode == .paint && !inspectorItem.isCollapsed)
        case #selector(toggleCheckerboard(_:)): on(settings.photoCheckerboard)
        case #selector(setViewerBackground(_:)): on(ViewerBackgroundSetting.allCases.indices.contains(item.tag) && ViewerBackgroundSetting.allCases[item.tag] == settings.photoBackground)
        case #selector(setSortOrder(_:)): on(ImageSortOrder.allCases.indices.contains(item.tag) && ImageSortOrder.allCases[item.tag] == settings.photoSortOrder)
        case #selector(selectTool(_:)): on(state.mode == .paint && ToolKind.allCases.indices.contains(item.tag) && ToolKind.allCases[item.tag] == toolSettings.tool)
        case #selector(AppActions.toggleImageInfo(_:)): on(state.showsImageInfo)
        case #selector(AppActions.toggleImageBrowser(_:)): on(state.showsImageBrowser)
        case #selector(AppActions.compareWithOriginal(_:)): on(viewer.ui.isComparing)
        case #selector(AppActions.startSlideshow(_:)):
            item.title = state.isSlideshowRunning ? String(localized: "Stop Slideshow", table: "Menu") : String(localized: "Slideshow", table: "Menu")
        default: break
        }
    }

    func isEnabled(_ action: Selector?, tag: Int) -> Bool {
        guard let action else { return false }
        let doc = imageDocument
        let hasDoc = doc != nil
        let hasImage = hasDoc && state.imageSize != nil
        let paint = state.mode == .paint
        let hasCanvas = canvas != nil
        let hasSelection = canvas?.selection != nil || canvas?.floating != nil
        let layerCount = canvas?.layers.count ?? 0
        let activeIndex = canvas?.activeLayerIndex
        let busy = state.isLoading

        switch action {
        // Mode / zoom
        case #selector(togglePaintMode(_:)): return hasImage && !busy
        case #selector(zoomIn(_:)): return hasImage && scrollView.magnification < ZoomLevels.maximum - 0.001
        case #selector(zoomOut(_:)): return hasImage && scrollView.magnification > ZoomLevels.minimum + 0.001
        case #selector(zoomToFit(_:)), #selector(zoomToFitWidth(_:)), #selector(zoomToFitHeight(_:)),
             #selector(zoomToActualSize(_:)), #selector(zoomToActualPixels(_:)), #selector(setCustomZoom(_:)):
            return hasImage

        // Navigation (Photo Mode browsing; also allowed from Paint with the save prompt)
        case #selector(showPreviousImage(_:)): return session.url(movingBy: -1, loop: settings.photoLoopNavigation) != nil
        case #selector(showNextImage(_:)): return session.url(movingBy: 1, loop: settings.photoLoopNavigation) != nil
        case #selector(showFirstImage(_:)): return (session.currentIndex ?? 0) > 0
        case #selector(showLastImage(_:)): return (session.currentIndex.map { $0 < session.urls.count - 1 }) ?? false
        case #selector(setSortOrder(_:)): return !session.urls.isEmpty

        // View
        case #selector(toggleStatusBar(_:)), #selector(toggleToolbar(_:)), #selector(toggleCheckerboard(_:)), #selector(setViewerBackground(_:)): return true
        case #selector(toggleToolPalette(_:)), #selector(toggleInspector(_:)): return paint
        case #selector(AppActions.toggleImageInfo(_:)): return hasImage
        case #selector(AppActions.toggleImageBrowser(_:)): return state.showsImageBrowser || (!paint && hasDoc && !state.isSlideshowRunning)
        case #selector(AppActions.startSlideshow(_:)): return state.isSlideshowRunning || (session.urls.count > 0 && hasImage && !paint && !busy)
        case #selector(AppActions.compareWithOriginal(_:)): return (hasCanvas || viewer.ui.isComparing) && doc?.fileURL != nil && doc?.isProject == false

        // File
        case #selector(revealInFinder(_:)), #selector(copyImagePath(_:)): return doc?.fileURL != nil
        case #selector(openInNewWindow(_:)): return hasDoc
        case #selector(shareImage(_:)): return hasImage
        case #selector(AppActions.exportImage(_:)), #selector(AppActions.saveAsProject(_:)): return hasImage && !busy
        case #selector(AppActions.grantFolderAccess(_:)): return doc?.fileURL != nil && !session.isExplicit

        // Edit
        case #selector(NSText.copy(_:)): return hasImage
        case #selector(NSText.cut(_:)), #selector(NSText.delete(_:)): return paint && hasSelection
        case #selector(NSText.paste(_:)), #selector(AppActions.pasteAsNewLayer(_:)):
            return paint && hasCanvas && ClipboardImage.hasImage()
        case #selector(AppActions.pasteAsNewImage(_:)): return ClipboardImage.hasImage()
        case #selector(NSText.selectAll(_:)): return paint && hasCanvas
        case #selector(AppActions.deselectAll(_:)): return paint && hasSelection

        // Image edits (materialize on demand, so also enabled in Photo Mode)
        case #selector(AppActions.rotateLeft(_:)), #selector(AppActions.rotateRight(_:)), #selector(AppActions.rotate180(_:)),
             #selector(AppActions.flipHorizontal(_:)), #selector(AppActions.flipVertical(_:)):
            return hasImage && !busy
        case #selector(AppActions.resizeImage(_:)), #selector(AppActions.resizeCanvas(_:)): return hasImage && !busy
        case #selector(AppActions.cropToSelection(_:)): return paint && hasSelection && !busy
        case #selector(AppActions.removeBackground(_:)), #selector(AppActions.copySubjectToNewLayer(_:)),
             #selector(AppActions.autoEnhance(_:)):
            return canRunSmartEdit

        // Layers
        case #selector(AppActions.newLayer(_:)), #selector(AppActions.duplicateLayer(_:)): return paint && hasCanvas
        case #selector(AppActions.deleteLayer(_:)): return paint && layerCount > 1
        case #selector(AppActions.mergeLayerDown(_:)): return paint && !busy && (activeIndex ?? 0) > 0
        case #selector(AppActions.flattenImage(_:)): return paint && !busy && layerCount > 1
        case #selector(AppActions.moveLayerUp(_:)): return paint && activeIndex.map { $0 < layerCount - 1 } ?? false
        case #selector(AppActions.moveLayerDown(_:)): return paint && (activeIndex ?? 0) > 0

        // Tools
        case #selector(selectTool(_:)): return hasImage
        case #selector(showColorPicker(_:)): return true
        case #selector(swapColors(_:)): return paint
        case #selector(increaseToolSize(_:)), #selector(decreaseToolSize(_:)): return paint

        default:
            return true
        }
    }
}

extension Notification.Name {
    /// Posted when a display-related setting changed so all windows re-apply view settings.
    static let viewSettingsDidChange = Notification.Name("ViewSettingsDidChange")
}
