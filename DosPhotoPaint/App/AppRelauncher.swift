import AppKit

/// Restarts the app (used after a language change).
///
/// Unsaved documents are reviewed first (standard save / don't save / cancel sheets). Only when
/// every document was resolved is a new instance launched and the current one terminated, so
/// cancelling a save leaves the running app untouched.
@MainActor
final class AppRelauncher: NSObject {
    private static let shared = AppRelauncher()

    static func relaunch() {
        NSDocumentController.shared.reviewUnsavedDocuments(
            withAlertTitle: String(localized: "Save changes before relaunching?", table: "Settings"),
            cancellable: true,
            delegate: shared,
            didReviewAllSelector: #selector(AppRelauncher.documentController(_:didReviewAll:contextInfo:)),
            contextInfo: nil)
    }

    @objc func documentController(_ controller: NSDocumentController, didReviewAll: Bool,
                                  contextInfo: UnsafeMutableRawPointer?) {
        guard didReviewAll else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    NSApp.presentError(error)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
