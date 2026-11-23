import XCTest
import AppKit
@testable import DosPhotoPaint

/// Photo Mode image browser listing, live background setting, browser toggling.
@MainActor
final class ImageBrowserTests: AppTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("browser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub/deeper"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("a-sub"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func png(_ rel: String) throws -> URL {
        let url = dir.appendingPathComponent(rel)
        let b = RasterBuffer(width: 8, height: 8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        b.fill(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        try ImageEncoder.encode(b.copyImage()!, as: .png).write(to: url)
        return url
    }

    func testListingRootOnlyAndRecursiveOrder() throws {
        _ = try png("img10.png"); _ = try png("img2.png")
        _ = try png("sub/s1.png"); _ = try png("sub/deeper/d1.png"); _ = try png("a-sub/a1.png")
        try Data("not an image".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        let flat = try XCTUnwrap(ImageBrowserModel.list(root: dir, recursive: false, order: .naturalName, limit: 100))
        XCTAssertEqual(flat.items.map(\.name), ["img2.png", "img10.png"], "natural order, root only, non-images skipped")

        let deep = try XCTUnwrap(ImageBrowserModel.list(root: dir, recursive: true, order: .naturalName, limit: 100))
        XCTAssertEqual(deep.items.map(\.name), ["img2.png", "img10.png", "a1.png", "s1.png", "d1.png"],
                       "root first, then subfolders in natural order")
        XCTAssertEqual(deep.items.map(\.folder), ["", "", "a-sub", "sub", "sub/deeper"])
        XCTAssertFalse(deep.truncated)
        XCTAssertNotNil(deep.items[0].fileSize)

        let capped = try XCTUnwrap(ImageBrowserModel.list(root: dir, recursive: true, order: .naturalName, limit: 2))
        XCTAssertEqual(capped.items.count, 2)
        XCTAssertTrue(capped.truncated)
    }

    func testUnreadableRootReportsNil() {
        XCTAssertNil(ImageBrowserModel.list(root: dir.appendingPathComponent("missing"), recursive: true, order: .name, limit: 10))
        XCTAssertNil(ImageBrowserModel.list(root: dir.appendingPathComponent("missing"), recursive: false, order: .name, limit: 10))
    }

    func testContainsIsPathComponentAware() {
        let root = URL(fileURLWithPath: "/a/b")
        XCTAssertTrue(ImageBrowserModel.contains(root, URL(fileURLWithPath: "/a/b")))
        XCTAssertTrue(ImageBrowserModel.contains(root, URL(fileURLWithPath: "/a/b/c")))
        XCTAssertFalse(ImageBrowserModel.contains(root, URL(fileURLWithPath: "/a/bc")))
    }

    func testModelLoadsFolderOfCurrentImageAndKeepsRootForSubfolders() async throws {
        let top = try png("top.png"); let inner = try png("sub/s1.png")
        let session = BrowsingSession(explicitURLs: nil)
        session.replace(with: [top], current: top)   // single file → not explicit
        let model = ImageBrowserModel()
        model.load(session: session, includeSubfolders: true, order: .naturalName)
        let deadline = Date(timeIntervalSinceNow: 10)
        while model.isLoading, Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(Set(model.items.map(\.name)), ["top.png", "s1.png"])
        XCTAssertEqual(model.rootFolder?.standardizedFileURL.path, dir.standardizedFileURL.path)
        // Opening an image in a subfolder keeps the browser rooted at the original folder.
        session.replace(with: [inner], current: inner)
        model.load(session: session, includeSubfolders: true, order: .naturalName)
        XCTAssertEqual(model.rootFolder?.standardizedFileURL.path, dir.standardizedFileURL.path)
    }

    func testBackgroundSettingAppliesLiveToOpenWindow() async throws {
        let settings = AppSettings.shared
        let old = settings.photoBackground
        defer { settings.photoBackground = old }
        settings.photoBackground = .black
        let wc = MainWindowController(initialMode: .photo, sessionURLs: nil)
        defer { wc.window?.close() }
        XCTAssertEqual(wc.scrollView.backgroundColor, ViewerBackgroundSetting.black.color)
        // Changed from the Settings window (no menu action, no other window event).
        settings.photoBackground = .white
        let deadline = Date(timeIntervalSinceNow: 5)
        while wc.scrollView.backgroundColor != ViewerBackgroundSetting.white.color, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(wc.scrollView.backgroundColor, ViewerBackgroundSetting.white.color)
    }

    func testBrowserToggleIsPhotoModeOnlyAndMenuIsWired() {
        let wc = MainWindowController(initialMode: .photo, sessionURLs: nil)
        defer { wc.window?.close() }
        wc.toggleImageBrowser(nil)
        XCTAssertTrue(wc.state.showsImageBrowser)
        wc.hideImageBrowser()
        XCTAssertFalse(wc.state.showsImageBrowser)
        XCTAssertTrue(MainWindowController.instancesRespond(to: #selector(AppActions.toggleImageBrowser(_:))))
        let items = MainMenu.build().items.flatMap { $0.submenu?.items ?? [] }
        XCTAssertTrue(items.contains { $0.action == #selector(AppActions.toggleImageBrowser(_:)) && $0.keyEquivalent == "b" })
    }
}
