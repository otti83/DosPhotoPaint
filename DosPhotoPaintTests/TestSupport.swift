import AppKit
import XCTest
@testable import DosPhotoPaint

/// Keeps the shared test host (one app process, one `DocumentController`) clean between tests:
/// no autosave timers (their temp directories are deleted by tearDown, which made AppKit log
/// "Autosaving: rescheduling the autosave because it failed"), and no documents or windows left
/// open after a test.
@MainActor
enum TestHost {
    static func prepare() {
        DocumentController.shared.autosavingDelay = 0
        closeEverything()
    }

    static func closeEverything() {
        for doc in DocumentController.shared.documents {
            doc.updateChangeCount(.changeCleared)
            doc.close()
        }
        // Windows created without a document (performance tests).
        for window in NSApp.windows where window.windowController is MainWindowController {
            (window.windowController as? MainWindowController)?.window?.close()
        }
    }
}

/// Base class for tests that create documents or windows.
@MainActor
class AppTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { TestHost.prepare() }
    }

    override func tearDown() {
        MainActor.assumeIsolated { TestHost.closeEverything() }
        super.tearDown()
    }
}
