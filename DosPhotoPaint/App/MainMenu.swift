import AppKit

/// Builds the main menu in code (standard macOS structure; items enable/disable through
/// responder-chain validation).
enum MainMenu {
    private static func t(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Menu") }

    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(imageMenu()))
        main.addItem(submenu(toolsMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        item.tag = tag
        menu.addItem(item)
        return item
    }

    // MARK: App

    private static func appMenu() -> NSMenu {
        let name = "DosPhotoPaint"
        let m = NSMenu(title: name)
        add(m, t("About \(name)"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        m.addItem(.separator())
        add(m, t("Settings…"), #selector(AppActions.showSettings(_:)), ",")
        m.addItem(.separator())
        let services = NSMenuItem(title: t("Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: t("Services"))
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        m.addItem(services)
        m.addItem(.separator())
        add(m, t("Hide \(name)"), #selector(NSApplication.hide(_:)), "h")
        add(m, t("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(m, t("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        m.addItem(.separator())
        add(m, t("Quit \(name)"), #selector(NSApplication.terminate(_:)), "q")
        return m
    }

    // MARK: File

    private static func fileMenu() -> NSMenu {
        let m = NSMenu(title: t("File"))
        add(m, t("New Canvas"), #selector(NSDocumentController.newDocument(_:)), "n")
        add(m, t("New from Clipboard"), #selector(AppActions.newFromClipboard(_:)), "n", [.command, .option])
        add(m, t("Open…"), #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenuItem(title: t("Open Recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: t("Open Recent"))
        // AppKit fills the menu that contains clearRecentDocuments: automatically.
        add(recentMenu, t("Clear Menu"), #selector(NSDocumentController.clearRecentDocuments(_:)))
        recent.submenu = recentMenu
        m.addItem(recent)
        add(m, t("Open in New Window"), #selector(AppActions.openInNewWindow(_:)))
        m.addItem(.separator())
        add(m, t("Close"), #selector(NSWindow.performClose(_:)), "w")
        add(m, t("Save…"), #selector(NSDocument.save(_:)), "s")
        add(m, t("Save As…"), #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        add(m, t("Duplicate"), #selector(NSDocument.duplicate(_:)))
        add(m, t("Save as Project…"), #selector(AppActions.saveAsProject(_:)))
        add(m, t("Export…"), #selector(AppActions.exportImage(_:)), "e", [.command, .shift])
        add(m, t("Revert to Saved"), #selector(NSDocument.revertToSaved(_:)))
        m.addItem(.separator())
        add(m, t("Show in Finder"), #selector(AppActions.revealInFinder(_:)), "r", [.command, .shift])
        add(m, t("Copy Image Path"), #selector(AppActions.copyImagePath(_:)), "c", [.command, .option])
        add(m, t("Allow Access to Folder…"), #selector(AppActions.grantFolderAccess(_:)))
        add(m, t("Share…"), #selector(AppActions.shareImage(_:)))
        m.addItem(.separator())
        add(m, t("Page Setup…"), #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        add(m, t("Print…"), #selector(NSDocument.printDocument(_:)), "p")
        return m
    }

    // MARK: Edit

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: t("Edit"))
        add(m, t("Undo"), Selector(("undo:")), "z")
        add(m, t("Redo"), Selector(("redo:")), "z", [.command, .shift])
        m.addItem(.separator())
        add(m, t("Cut"), #selector(NSText.cut(_:)), "x")
        add(m, t("Copy"), #selector(NSText.copy(_:)), "c")
        add(m, t("Paste"), #selector(NSText.paste(_:)), "v")
        add(m, t("Paste as New Layer"), #selector(AppActions.pasteAsNewLayer(_:)), "v", [.command, .shift])
        add(m, t("Paste as New Image"), #selector(AppActions.pasteAsNewImage(_:)), "v", [.command, .option])
        add(m, t("Delete"), #selector(NSText.delete(_:)))
        add(m, t("Select All"), #selector(NSText.selectAll(_:)), "a")
        add(m, t("Deselect"), #selector(AppActions.deselectAll(_:)), "a", [.command, .shift])
        m.addItem(.separator())
        // Standard items AppKit appends (Start Dictation, Emoji & Symbols) are added automatically.
        return m
    }

    // MARK: View

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: t("View"))
        add(m, t("Photo / Paint Mode"), #selector(AppActions.togglePaintMode(_:)), "e")
        m.addItem(.separator())
        add(m, t("Zoom In"), #selector(AppActions.zoomIn(_:)), "+")
        let zoomInAlt = add(m, t("Zoom In"), #selector(AppActions.zoomIn(_:)), "=")
        zoomInAlt.isHidden = true
        zoomInAlt.allowsKeyEquivalentWhenHidden = true
        add(m, t("Zoom Out"), #selector(AppActions.zoomOut(_:)), "-")
        add(m, t("Zoom to Fit"), #selector(AppActions.zoomToFit(_:)), "0")
        add(m, t("Actual Size (100%)"), #selector(AppActions.zoomToActualSize(_:)), "1")
        add(m, t("Actual Pixels"), #selector(AppActions.zoomToActualPixels(_:)), "1", [.command, .option])
        add(m, t("Fit Width"), #selector(AppActions.zoomToFitWidth(_:)))
        add(m, t("Fit Height"), #selector(AppActions.zoomToFitHeight(_:)))
        add(m, t("Zoom To…"), #selector(AppActions.setCustomZoom(_:)), "z", [.command, .option])
        m.addItem(.separator())
        add(m, t("Previous Image"), #selector(AppActions.showPreviousImage(_:)), "[")
        add(m, t("Next Image"), #selector(AppActions.showNextImage(_:)), "]")
        add(m, t("First Image"), #selector(AppActions.showFirstImage(_:)), "[", [.command, .option])
        add(m, t("Last Image"), #selector(AppActions.showLastImage(_:)), "]", [.command, .option])
        let sort = NSMenuItem(title: t("Sort Images By"), action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: t("Sort Images By"))
        for (i, order) in ImageSortOrder.allCases.enumerated() {
            add(sortMenu, order.localizedName, #selector(AppActions.setSortOrder(_:)), tag: i)
        }
        sort.submenu = sortMenu
        m.addItem(sort)
        m.addItem(.separator())
        add(m, t("Slideshow"), #selector(AppActions.startSlideshow(_:)), "f", [.command, .shift])
        add(m, t("Image Browser"), #selector(AppActions.toggleImageBrowser(_:)), "b")
        add(m, t("Image Info"), #selector(AppActions.toggleImageInfo(_:)), "i")
        add(m, t("Compare with Original"), #selector(AppActions.compareWithOriginal(_:)), "o", [.command, .option])
        m.addItem(.separator())
        let bg = NSMenuItem(title: t("Background"), action: nil, keyEquivalent: "")
        bg.submenu = MainWindowController.viewerBackgroundMenu()
        m.addItem(bg)
        add(m, t("Transparency Checkerboard"), #selector(AppActions.toggleCheckerboard(_:)))
        m.addItem(.separator())
        add(m, t("Hide Toolbar"), #selector(AppActions.toggleToolbar(_:)), "t", [.command, .option])
        add(m, t("Show Status Bar"), #selector(AppActions.toggleStatusBar(_:)), "/", [.command])
        add(m, t("Show Tool Palette"), #selector(AppActions.toggleToolPalette(_:)), "1", [.command, .control])
        add(m, t("Show Inspector"), #selector(AppActions.toggleInspector(_:)), "2", [.command, .control])
        m.addItem(.separator())
        add(m, t("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        return m
    }

    // MARK: Image

    private static func imageMenu() -> NSMenu {
        let m = NSMenu(title: t("Image"))
        add(m, t("Rotate Left"), #selector(AppActions.rotateLeft(_:)), "l")
        add(m, t("Rotate Right"), #selector(AppActions.rotateRight(_:)), "r")
        add(m, t("Rotate 180°"), #selector(AppActions.rotate180(_:)))
        add(m, t("Flip Horizontal"), #selector(AppActions.flipHorizontal(_:)))
        add(m, t("Flip Vertical"), #selector(AppActions.flipVertical(_:)))
        m.addItem(.separator())
        add(m, t("Resize Image…"), #selector(AppActions.resizeImage(_:)), "r", [.command, .option])
        add(m, t("Canvas Size…"), #selector(AppActions.resizeCanvas(_:)), "c", [.command, .option, .shift])
        add(m, t("Crop to Selection"), #selector(AppActions.cropToSelection(_:)), "k")
        m.addItem(.separator())
        let smart = NSMenuItem(title: t("Smart Edit"), action: nil, keyEquivalent: "")
        smart.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        smart.submenu = MainWindowController.smartEditMenu()
        m.addItem(smart)
        m.addItem(.separator())
        let layers = NSMenuItem(title: t("Layer"), action: nil, keyEquivalent: "")
        let lm = NSMenu(title: t("Layer"))
        add(lm, t("New Layer"), #selector(AppActions.newLayer(_:)), "n", [.command, .shift])
        add(lm, t("Duplicate Layer"), #selector(AppActions.duplicateLayer(_:)), "j")
        add(lm, t("Delete Layer"), #selector(AppActions.deleteLayer(_:)))
        lm.addItem(.separator())
        // No ⇧⌘[ / ⇧⌘]: those are the system shortcuts for switching window tabs.
        add(lm, t("Move Layer Up"), #selector(AppActions.moveLayerUp(_:)))
        add(lm, t("Move Layer Down"), #selector(AppActions.moveLayerDown(_:)))
        lm.addItem(.separator())
        add(lm, t("Merge Down"), #selector(AppActions.mergeLayerDown(_:)), "e", [.command, .option])
        add(lm, t("Flatten Image"), #selector(AppActions.flattenImage(_:)), "f", [.command, .option, .shift])
        layers.submenu = lm
        m.addItem(layers)
        return m
    }

    // MARK: Tools

    private static func toolsMenu() -> NSMenu {
        let m = NSMenu(title: t("Tools"))
        for (i, tool) in ToolKind.allCases.enumerated() {
            // Single-key tool shortcuts (P, B, E…) are handled by the canvas view so they can never
            // fire while typing in a text field; menu key equivalents without modifiers would.
            add(m, tool.localizedName, #selector(AppActions.selectTool(_:)), tag: i)
        }
        m.addItem(.separator())
        add(m, t("Swap Colors"), #selector(AppActions.swapColors(_:)))
        add(m, t("Show Colors"), #selector(AppActions.showColorPicker(_:)), "c", [.command, .shift])
        // NSFontManager is not in the responder chain, so it must be the explicit target.
        add(m, t("Show Fonts"), #selector(NSFontManager.orderFrontFontPanel(_:)), "t").target = NSFontManager.shared
        m.addItem(.separator())
        add(m, t("Increase Size"), #selector(AppActions.increaseToolSize(_:)))
        add(m, t("Decrease Size"), #selector(AppActions.decreaseToolSize(_:)))
        return m
    }

    // MARK: Window / Help

    private static func windowMenu() -> NSMenu {
        let m = NSMenu(title: t("Window"))
        add(m, t("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(m, t("Zoom"), #selector(NSWindow.performZoom(_:)))
        m.addItem(.separator())
        add(m, t("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        return m
    }

    private static func helpMenu() -> NSMenu {
        let m = NSMenu(title: t("Help"))
        add(m, t("DosPhotoPaint Help"), #selector(AppActions.showHelp(_:)), "?")
        add(m, t("Keyboard Shortcuts"), #selector(AppActions.showKeyboardShortcuts(_:)))
        return m
    }
}

// MARK: - Display names for menu enums

extension ImageSortOrder {
    var localizedName: String {
        switch self {
        case .naturalName: String(localized: "Name (Natural)", table: "Menu")
        case .name: String(localized: "Name", table: "Menu")
        case .modificationDate: String(localized: "Date Modified", table: "Menu")
        case .creationDate: String(localized: "Date Created", table: "Menu")
        }
    }
}

extension ViewerBackgroundSetting {
    var localizedName: String {
        switch self {
        case .darkGray: String(localized: "Dark Gray", table: "Menu")
        case .black: String(localized: "Black", table: "Menu")
        case .lightGray: String(localized: "Light Gray", table: "Menu")
        case .white: String(localized: "White", table: "Menu")
        case .window: String(localized: "Window Background", table: "Menu")
        }
    }
}
