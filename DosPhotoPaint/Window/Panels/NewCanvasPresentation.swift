import SwiftUI

/// Shows the New Canvas dialog: as a sheet on the key document window, otherwise as an app-modal panel.
enum NewCanvasPresentation {
    static func present(initial: NewCanvasSpec, clipboardSize: (width: Int, height: Int)?,
                        completion: @escaping (NewCanvasSpec?) -> Void) {
        if let controller = NSApp.keyWindow?.windowController as? MainWindowController {
            controller.presentSheet { dismiss in
                NewCanvasSheet(initial: initial, clipboardSize: clipboardSize,
                               onCreate: { dismiss(); completion($0) },
                               onCancel: { dismiss(); completion(nil) })
            }
            return
        }
        // No window: app-modal panel.
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled]
        var result: NewCanvasSpec?
        host.rootView = AnyView(NewCanvasSheet(initial: initial, clipboardSize: clipboardSize,
                                               onCreate: { result = $0; NSApp.stopModal() },
                                               onCancel: { NSApp.stopModal() }))
        panel.center()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        completion(result)
    }
}
