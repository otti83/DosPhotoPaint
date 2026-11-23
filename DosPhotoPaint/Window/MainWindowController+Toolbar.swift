import AppKit

extension NSToolbarItem.Identifier {
    static let previousImage = Self("previousImage")
    static let nextImage = Self("nextImage")
    static let zoomIn = Self("zoomIn")
    static let zoomOut = Self("zoomOut")
    static let zoomFit = Self("zoomFit")
    static let zoomActual = Self("zoomActual")
    static let rotateLeft = Self("rotateLeft")
    static let rotateRight = Self("rotateRight")
    static let flipHorizontal = Self("flipHorizontal")
    static let imageInfo = Self("imageInfo")
    static let slideshow = Self("slideshow")
    static let share = Self("share")
    static let modeSwitch = Self("modeSwitch")
    static let newCanvas = Self("newCanvas")
    static let openFile = Self("openFile")
    static let saveFile = Self("saveFile")
    static let undo = Self("undo")
    static let redo = Self("redo")
    static let crop = Self("crop")
    static let resize = Self("resize")
    static let inspector = Self("inspector")
    static let viewerBackground = Self("viewerBackground")
    static let smartEdit = Self("smartEdit")
    static let imageBrowser = Self("imageBrowser")
}

/// Toolbar construction. Photo and Paint each get their own `NSToolbar`; switching modes swaps
/// `window.toolbar` (identifiers differ so each keeps its own user customization).
extension MainWindowController: NSToolbarDelegate {
    var photoToolbar: NSToolbar { toolbar(for: .photo) }
    var paintToolbar: NSToolbar { toolbar(for: .paint) }

    private func toolbar(for mode: WindowMode) -> NSToolbar {
        if let cached = toolbars[mode] { return cached }
        // ".v2": the default item sets changed in 0.1.0 (background / Smart Edit items); a fresh
        // identifier makes existing users see them instead of their autosaved older configuration.
        let tb = NSToolbar(identifier: mode == .photo ? Self.photoToolbarID : Self.paintToolbarID)
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = true
        tb.autosavesConfiguration = true
        toolbars[mode] = tb
        return tb
    }

    static let photoToolbarID = "PhotoToolbar.v3"
    static let paintToolbarID = "PaintToolbar.v3"

    func installToolbars() {
        window?.toolbar = state.mode == .photo ? photoToolbar : paintToolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if toolbar.identifier == Self.photoToolbarID {
            return [.imageBrowser, .previousImage, .nextImage, .space, .zoomOut, .zoomIn, .zoomFit, .zoomActual, .space,
                    .rotateLeft, .rotateRight, .flexibleSpace, .viewerBackground, .imageInfo, .slideshow, .share, .modeSwitch]
        }
        return [.newCanvas, .openFile, .saveFile, .space, .undo, .redo, .space, .crop, .resize, .rotateLeft,
                .rotateRight, .flipHorizontal, .smartEdit, .flexibleSpace, .zoomOut, .zoomIn, .zoomFit, .inspector, .modeSwitch]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ids = toolbarDefaultItemIdentifiers(toolbar)
        for id in [.zoomActual, .imageInfo, .share, .flipHorizontal, .previousImage, .nextImage, .viewerBackground, .smartEdit, .imageBrowser,
                   .space, .flexibleSpace] as [NSToolbarItem.Identifier] where !ids.contains(id) || id == .space || id == .flexibleSpace {
            ids.append(id)
        }
        return ids
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func t(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Toolbar") }
        func button(_ label: String, _ symbol: String, _ action: Selector) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.action = action
            item.isBordered = true
            item.autovalidates = true
            return item
        }
        switch id {
        case .previousImage: return button(t("Previous"), "chevron.left", #selector(AppActions.showPreviousImage(_:)))
        case .nextImage: return button(t("Next"), "chevron.right", #selector(AppActions.showNextImage(_:)))
        case .zoomIn: return button(t("Zoom In"), "plus.magnifyingglass", #selector(AppActions.zoomIn(_:)))
        case .zoomOut: return button(t("Zoom Out"), "minus.magnifyingglass", #selector(AppActions.zoomOut(_:)))
        case .zoomFit: return button(t("Fit"), "arrow.up.left.and.down.right.magnifyingglass", #selector(AppActions.zoomToFit(_:)))
        case .zoomActual: return button(t("Actual Size"), "1.magnifyingglass", #selector(AppActions.zoomToActualSize(_:)))
        case .rotateLeft: return button(t("Rotate Left"), "rotate.left", #selector(AppActions.rotateLeft(_:)))
        case .rotateRight: return button(t("Rotate Right"), "rotate.right", #selector(AppActions.rotateRight(_:)))
        case .flipHorizontal: return button(t("Flip"), "arrow.left.and.right.righttriangle.left.righttriangle.right", #selector(AppActions.flipHorizontal(_:)))
        case .imageInfo: return button(t("Info"), "info.circle", #selector(AppActions.toggleImageInfo(_:)))
        case .slideshow: return button(t("Slideshow"), "play.rectangle", #selector(AppActions.startSlideshow(_:)))
        case .imageBrowser: return button(t("Browse"), "square.grid.2x2", #selector(AppActions.toggleImageBrowser(_:)))
        case .newCanvas: return button(t("New"), "doc.badge.plus", #selector(NSDocumentController.newDocument(_:)))
        case .openFile: return button(t("Open"), "folder", #selector(NSDocumentController.openDocument(_:)))
        case .saveFile: return button(t("Save"), "square.and.arrow.down", #selector(NSDocument.save(_:)))
        case .undo: return button(t("Undo"), "arrow.uturn.backward", Selector(("undo:")))
        case .redo: return button(t("Redo"), "arrow.uturn.forward", Selector(("redo:")))
        case .crop: return button(t("Crop"), "crop", #selector(AppActions.cropToSelection(_:)))
        case .resize: return button(t("Resize"), "arrow.up.left.and.arrow.down.right", #selector(AppActions.resizeImage(_:)))
        case .inspector: return button(t("Inspector"), "sidebar.right", #selector(AppActions.toggleInspector(_:)))
        case .viewerBackground:
            // Pull-down of background colours; the items validate (checkmark) through the responder chain.
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = t("Background")
            item.paletteLabel = t("Background")
            item.toolTip = t("Background Color")
            item.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: t("Background"))
            item.menu = Self.viewerBackgroundMenu()
            item.showsIndicator = true
            return item
        case .smartEdit:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = t("Smart Edit")
            item.paletteLabel = t("Smart Edit")
            item.toolTip = t("Smart Edit (on-device macOS image analysis)")
            item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: t("Smart Edit"))
            item.menu = Self.smartEditMenu()
            item.showsIndicator = true
            return item
        case .share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: id)
            item.label = t("Share")
            item.paletteLabel = t("Share")
            item.delegate = self
            return item
        case .modeSwitch:
            let control = NSSegmentedControl(labels: [t("Photo"), t("Paint")], trackingMode: .selectOne,
                                             target: self, action: #selector(modeSegmentChanged(_:)))
            control.selectedSegment = state.mode == .photo ? 0 : 1
            control.setToolTip(t("View the image"), forSegment: 0)
            control.setToolTip(t("Edit the image"), forSegment: 1)
            control.setImage(NSImage(systemSymbolName: "photo", accessibilityDescription: nil), forSegment: 0)
            control.setImage(NSImage(systemSymbolName: "paintbrush", accessibilityDescription: nil), forSegment: 1)
            control.setAccessibilityLabel(t("Mode"))
            modeControls.append(control)
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = control
            item.label = t("Mode")
            item.paletteLabel = t("Mode")
            return item
        default:
            return nil
        }
    }

    /// Menu of the Photo Mode background colours (toolbar, context menu).
    static func viewerBackgroundMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Background", table: "Menu"))
        for (i, b) in ViewerBackgroundSetting.allCases.enumerated() {
            let item = NSMenuItem(title: b.localizedName, action: #selector(AppActions.setViewerBackground(_:)), keyEquivalent: "")
            item.tag = i
            item.image = Self.swatch(b.color)
            menu.addItem(item)
        }
        return menu
    }

    /// Menu of the Smart Edit actions (toolbar, Image menu, context menu).
    static func smartEditMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Smart Edit", table: "Menu"))
        for (title, action) in [(String(localized: "Remove Background", table: "Menu"), #selector(AppActions.removeBackground(_:))),
                                (String(localized: "Copy Subject to New Layer", table: "Menu"), #selector(AppActions.copySubjectToNewLayer(_:))),
                                (String(localized: "Auto Enhance", table: "Menu"), #selector(AppActions.autoEnhance(_:)))] {
            if action == #selector(AppActions.autoEnhance(_:)) { menu.addItem(.separator()) }
            menu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: ""))
        }
        return menu
    }

    /// Small colour swatch for menu items.
    private static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.secondaryLabelColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }

    @objc func modeSegmentChanged(_ sender: NSSegmentedControl) {
        setMode(sender.selectedSegment == 1 ? .paint : .photo)
        syncModeControls()
    }

    /// Keeps all mode segmented controls in sync with `state.mode`.
    func syncModeControls() {
        modeControls.removeAll { $0.window == nil && $0.superview == nil }
        for c in modeControls { c.selectedSegment = state.mode == .photo ? 0 : 1 }
    }
}

extension MainWindowController: NSSharingServicePickerToolbarItemDelegate {
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        sharingItems()
    }

    /// File URL when the image is saved and unmodified, otherwise the rendered image.
    func sharingItems() -> [Any] {
        guard let doc = imageDocument else { return [] }
        if let url = doc.fileURL, !doc.isDocumentEdited { return [url] }
        if let canvas = doc.canvas, let image = canvas.flattenedImage() {
            return [NSImage(cgImage: image, size: canvas.size)]
        }
        return []
    }
}
