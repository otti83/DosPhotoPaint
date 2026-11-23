import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, photo, paint, save, slideshow, performance, shortcuts
    var id: String { rawValue }
}

/// Hosts the SwiftUI settings view in a standard preferences window (⌘,).
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private let selection = SettingsSelection()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.title = String(localized: "Settings", table: "Settings")
        window.contentMinSize = NSSize(width: 720, height: 480)
        // New autosave name: frames saved for the old, narrower tab layout would be too small.
        window.setFrameAutosaveName("SettingsWindow.sidebar")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: SettingsView(selection: selection))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(tab: SettingsTab?) {
        if let tab { selection.tab = tab }
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@Observable
final class SettingsSelection {
    var tab: SettingsTab = .general
}
