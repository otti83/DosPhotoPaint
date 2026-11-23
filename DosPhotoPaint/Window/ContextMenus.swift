import AppKit

/// Right-click menu on the canvas (mode-dependent).
enum ContextMenus {
    static func menu(for controller: MainWindowController, event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector) {
            m.addItem(NSMenuItem(title: title, action: action, keyEquivalent: ""))
        }
        func t(_ key: String.LocalizationValue) -> String { String(localized: key, table: "Menu") }
        if controller.state.mode == .photo {
            add(t("Copy"), #selector(NSText.copy(_:)))
            add(t("Show in Finder"), #selector(AppActions.revealInFinder(_:)))
            add(t("Copy Image Path"), #selector(AppActions.copyImagePath(_:)))
            m.addItem(.separator())
            add(t("Rotate Left"), #selector(AppActions.rotateLeft(_:)))
            add(t("Rotate Right"), #selector(AppActions.rotateRight(_:)))
            m.addItem(.separator())
            let bg = NSMenuItem(title: t("Background"), action: nil, keyEquivalent: "")
            bg.submenu = MainWindowController.viewerBackgroundMenu()
            m.addItem(bg)
            m.addItem(.separator())
            add(t("Image Info"), #selector(AppActions.toggleImageInfo(_:)))
            add(t("Switch to Paint Mode"), #selector(AppActions.togglePaintMode(_:)))
        } else {
            add(t("Cut"), #selector(NSText.cut(_:)))
            add(t("Copy"), #selector(NSText.copy(_:)))
            add(t("Paste"), #selector(NSText.paste(_:)))
            add(t("Delete"), #selector(NSText.delete(_:)))
            m.addItem(.separator())
            add(t("Select All"), #selector(NSText.selectAll(_:)))
            add(t("Deselect"), #selector(AppActions.deselectAll(_:)))
            add(t("Crop to Selection"), #selector(AppActions.cropToSelection(_:)))
            m.addItem(.separator())
            let smart = NSMenuItem(title: t("Smart Edit"), action: nil, keyEquivalent: "")
            smart.submenu = MainWindowController.smartEditMenu()
            m.addItem(smart)
            m.addItem(.separator())
            add(t("Switch to Photo Mode"), #selector(AppActions.togglePaintMode(_:)))
        }
        return m
    }
}
