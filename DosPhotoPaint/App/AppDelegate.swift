import AppKit

/// Application lifecycle. Launch-mode decisions follow AppKit's Apple Event semantics
/// (see docs/ARCHITECTURE.md §2) — no timers or delays.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when the process is the host of an XCTest bundle.
    static var isRunningUnitTests: Bool { AppRuntime.isUnitTestHost }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The first NSDocumentController instantiated becomes the shared one.
        _ = DocumentController()
        NSApp.mainMenu = MainMenu.build()
        AppSettings.shared.applySystemIntegration()
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ImageCache.shared  // installs the memory-pressure handler
        SettingsLiveApplier.shared.install()
        LaunchTiming.markDidFinishLaunching()
        // After the launch window is up, so the explanation appears in front of it.
        DispatchQueue.main.async { FileAccess.offerFullDiskAccessOnFirstLaunch() }
    }

    // MARK: Launch / reopen

    /// Called only for a launch without documents (`oapp`) or a Dock reopen with no windows.
    /// Not called when Finder opened files (`odoc`) or windows were restored.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if Self.isRunningUnitTests { return false }
        switch AppSettings.shared.startupMode {
        case .automatic, .paint:
            return true
        case .photo:
            DocumentController.shared.openDocument(nil)
            return false
        }
    }

    /// The automatic untitled canvas (launch, Dock reopen) opens the default canvas directly: only the
    /// explicit New Canvas command (`DocumentController.newDocument(_:)`) shows the dialog.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        do {
            try DocumentController.shared.openUntitledDocumentAndDisplay(true)
            return true
        } catch {
            NSApp.presentError(error)
            return false
        }
    }

    /// Non-document URL opens. For document types AppKit routes Finder opens directly to
    /// `DocumentController.openDocument(withContentsOf:display:)`; kept for completeness.
    func application(_ application: NSApplication, open urls: [URL]) {
        DocumentController.shared.openForViewing(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        // Bring back a minimized window instead of creating a new canvas.
        if let minimized = NSApp.windows.first(where: { $0.isMiniaturized && $0.windowController is MainWindowController }) {
            minimized.deminiaturize(nil)
            return false
        }
        return true  // AppKit then asks applicationShouldOpenUntitledFile → new Paint canvas
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: App-level actions

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show(tab: nil)
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        SettingsWindowController.shared.show(tab: .shortcuts)
    }

    @objc func showHelp(_ sender: Any?) {
        HelpWindowController.shared.show()
    }

    @objc func newFromClipboard(_ sender: Any?) {
        guard let image = ClipboardImage.readImage() else { NSSound.beep(); return }
        do {
            let doc = try ImageDocument(newFrom: image)
            DocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc func pasteAsNewImage(_ sender: Any?) { newFromClipboard(sender) }
}

