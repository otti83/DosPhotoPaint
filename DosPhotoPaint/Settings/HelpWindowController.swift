import AppKit
import SwiftUI

/// Small built-in help window (Help > DosPhotoPaint Help).
final class HelpWindowController: NSWindowController {
    static let shared = HelpWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.title = String(localized: "DosPhotoPaint Help", table: "Settings")
        window.setFrameAutosaveName("HelpWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: HelpView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Opening Images", "photo.on.rectangle",
                        "Double-click an image in Finder, drop files onto the Dock icon or a window, or choose File > Open. Images open in Photo Mode, and the other images in the same folder can be browsed with the arrow keys. If macOS has not granted access to the folder, use File > Allow Access to Folder.")
                section("Photo Mode and Paint Mode", "paintbrush",
                        "Photo Mode is for viewing: zoom, browse, rotate, and run a slideshow. Press ⌘E or use the toolbar to switch to Paint Mode, which adds the tool palette, inspector, and layers. Zoom and position are kept when you switch.")
                section("Editing", "pencil.and.outline",
                        "Pick a tool in the palette or press its letter key (see Shortcuts in Settings). Every stroke or change is one undo step; ⌘Z and ⇧⌘Z step through the history. Use the Image menu to resize, crop, rotate, or flip, and the Layers menu to work with layers.")
                section("Saving", "square.and.arrow.down",
                        "Nothing is written until you save. Save writes back to the original file, Save As and Export choose a format, and Save as Project keeps all layers in a .dpp file. Saving a layered image as PNG or JPEG flattens it, and you will be asked first.")
                section("Settings", "gearshape",
                        "Open Settings with ⌘, to change language, appearance, viewer behavior, defaults for new canvases, save options, and performance. Help > Keyboard Shortcuts lists every shortcut.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func section(_ title: LocalizedStringKey, _ symbol: String, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text(title, tableName: "Settings").font(.headline) } icon: { Image(systemName: symbol) }
            Text(body, tableName: "Settings").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
