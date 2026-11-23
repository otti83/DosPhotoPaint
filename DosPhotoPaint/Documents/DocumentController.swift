import AppKit
import UniformTypeIdentifiers

/// App-wide document controller. Instantiated first in `AppDelegate.applicationWillFinishLaunching`
/// (the first NSDocumentController created becomes `.shared`).
final class DocumentController: NSDocumentController {
    override class var shared: DocumentController {
        // swiftlint:disable:next force_cast
        super.shared as! DocumentController
    }

    /// Untitled canvases save as the user's preferred image format by default.
    override var defaultType: String? {
        let preferred: UTType = switch AppSettings.shared.saveDefaultFormat {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .bmp: .bmp
        }
        return ImageTypes.isWritable(preferred) ? preferred.identifier : UTType.png.identifier
    }

    /// AppKit queries this on its private "Document Recents" queue, so it must not be
    /// main-actor isolated. UserDefaults is thread-safe; the value is clamped like AppSettings does.
    nonisolated override var maximumRecentDocumentCount: Int {
        let stored = (AppRuntime.defaults.object(forKey: SettingsKey.recentDocumentsLimit) as? NSNumber)?.intValue ?? 20
        return min(max(stored, AppSettings.recentDocumentsRange.lowerBound), AppSettings.recentDocumentsRange.upperBound)
    }

    /// Restrict the Open panel to formats this Mac can actually decode, plus projects.
    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.allowedContentTypes = [ImageTypes.project] + ImageTypes.readable
        openPanel.allowsMultipleSelection = true
        return super.runModalOpenPanel(openPanel, forTypes: nil)
    }

    /// Open panel results go through the same path as Finder (Photo Mode, one session for many files).
    override func openDocument(_ sender: Any?) {
        beginOpenPanel { [weak self] urls in
            guard let self, let urls, !urls.isEmpty else { return }
            self.openForViewing(urls)
        }
    }

    // MARK: - New Canvas

    /// Asks the user for the new canvas parameters; calls `completion(nil)` on cancel. Replaceable so tests
    /// never block on a dialog. Only `newDocument(_:)` uses it: the untitled canvas AppKit creates at launch
    /// or on a Dock reopen goes through `openUntitledDocumentAndDisplay` and never shows the dialog.
    var newCanvasPresenter: (_ initial: NewCanvasSpec, _ completion: @escaping (NewCanvasSpec?) -> Void) -> Void = { initial, completion in
        let clipboard = ClipboardImage.readImage().map { (width: $0.width, height: $0.height) }
        NewCanvasPresentation.present(initial: initial, clipboardSize: clipboard, completion: completion)
    }

    /// File > New Canvas / toolbar "New": ask for size and background, then create the canvas.
    override func newDocument(_ sender: Any?) {
        newCanvasPresenter(.settingsDefault()) { [weak self] spec in
            guard let self, let spec else { return }
            do { _ = try self.createCanvas(spec) } catch { NSApp.presentError(error) }
        }
    }

    /// Creates and shows an untitled canvas with the given parameters.
    @discardableResult
    func createCanvas(_ spec: NewCanvasSpec) throws -> ImageDocument {
        let doc = try ImageDocument(type: defaultType ?? UTType.png.identifier, canvas: spec)
        addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        return doc
    }

    // MARK: - Coalescing external opens

    private typealias OpenCompletion = (NSDocument?, Bool, (any Error)?) -> Void
    private var pendingOpens: [(url: URL, completion: OpenCompletion)] = []

    /// Finder ("Open With", double-click, multi-selection), Open Recent and drops on the Dock icon
    /// arrive here with `display == true`, one call per file, all within the same event dispatch
    /// (AppKit bypasses `application(_:open:)` for document-based apps). The calls are collected and
    /// handled together at the end of the current run-loop pass so that a multi-selection becomes
    /// one browsing session instead of one window per file. This is event coalescing, not a delay.
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        guard displayDocument else {
            super.openDocument(withContentsOf: url, display: false, completionHandler: completionHandler)
            return
        }
        pendingOpens.append((url, completionHandler))
        if pendingOpens.count == 1 {
            RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) { [weak self] in
                MainActor.assumeIsolated { self?.flushPendingOpens() }
            }
        }
    }

    private func flushPendingOpens() {
        let batch = pendingOpens
        pendingOpens.removeAll()
        guard !batch.isEmpty else { return }
        openForViewing(batch.map(\.url)) { results in
            for item in batch {
                let key = item.url.standardizedFileURL
                if let doc = results[key] {
                    item.completion(doc, false, nil)
                } else {
                    // Part of a browsing session (no own window) or failed (already reported).
                    item.completion(nil, false, CocoaError(.userCancelled))
                }
            }
        }
    }

    // MARK: - Finder / Open entry point

    /// Opens files as Finder does: images in Photo Mode, projects in Paint Mode.
    ///
    /// - One image: a window browsing the image's folder.
    /// - Several images: a single window whose browsing session is exactly those images.
    /// - Files already open: their existing window is brought to front (no duplicates).
    func openForViewing(_ urls: [URL], completion: (([URL: NSDocument]) -> Void)? = nil) {
        var images: [URL] = []
        var projects: [URL] = []
        var unsupported: [URL] = []
        for url in urls.map(\.standardizedFileURL) {
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: url.pathExtension.lowercased())
            if let type, type.conforms(to: ImageTypes.project) { projects.append(url) }
            else if let type, ImageTypes.isReadableImage(type) { images.append(url) }
            else { unsupported.append(url) }
        }

        // The first image is shown as soon as its window exists. Building the document and the
        // window takes ~200 ms (Debug), the decode needs neither, so start it right now; the
        // window's own request joins the in-flight decode (ImageCache shares them).
        let first = images.count > 1 ? BrowsingSession.sorted(images, by: AppSettings.shared.photoSortOrder)[0] : images.first
        if let first, document(for: first) == nil {
            let budget = MainWindowController.displayPixelBudget(for: nil)
            Task { _ = try? await ImageCache.shared.displayImage(for: first, maxPixelSize: budget) }
        }

        var results: [URL: NSDocument] = [:]
        let group = DispatchGroup()
        func record(_ url: URL, _ doc: NSDocument?) {
            if let doc { results[url] = doc }
            group.leave()
        }

        for url in projects {
            group.enter()
            open(url, context: .init(mode: .paint, sessionURLs: nil)) { record(url, $0) }
        }

        if images.count == 1 {
            group.enter()
            open(images[0], context: .init(mode: .photo, sessionURLs: nil)) { record(images[0], $0) }
        } else if images.count > 1 {
            let sorted = BrowsingSession.sorted(images, by: AppSettings.shared.photoSortOrder)
            // Bring an already open file's window forward rather than creating a duplicate.
            if let existing = sorted.lazy.compactMap({ self.document(for: $0) }).first {
                existing.showWindows()
                (existing.windowControllers.first as? MainWindowController)?.replaceSession(with: sorted, current: existing.fileURL)
                if let url = existing.fileURL?.standardizedFileURL { results[url] = existing }
            } else {
                group.enter()
                openFirstReadable(of: sorted) { url, doc, unreadable in
                    if let url { record(url, doc) } else { group.leave() }
                    if !unreadable.isEmpty {
                        let names = unreadable.map(\.lastPathComponent).joined(separator: ", ")
                        self.problemPresenter(String(localized: "Some files could not be opened", table: "Documents"),
                                              String(localized: "These files could not be read: \(names)", table: "Documents"))
                    }
                }
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { completion?(results) } }

        if !unsupported.isEmpty {
            let names = unsupported.map(\.lastPathComponent).joined(separator: ", ")
            problemPresenter(String(localized: "Some files could not be opened", table: "Documents"),
                             String(localized: "These files are not in a supported image format: \(names)", table: "Documents"))
        }
    }

    /// Shows a "could not open" problem to the user. Replaceable so tests never block on a modal alert.
    var problemPresenter: (_ message: String, _ detail: String) -> Void = { message, detail in
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// Opens the first file of `sorted` (session order) that can be read as the window's document;
    /// files that fail are dropped from the browsing session and reported once through `unreadable`.
    /// Calls `completion(nil, nil, unreadable)` when no file could be opened.
    private func openFirstReadable(of sorted: [URL], failed: [URL] = [],
                                   completion: @escaping (_ opened: URL?, _ doc: NSDocument?, _ unreadable: [URL]) -> Void) {
        guard let candidate = sorted.first(where: { !failed.contains($0) }) else { completion(nil, nil, failed); return }
        let session = sorted.filter { !failed.contains($0) }
        open(candidate, context: .init(mode: .photo, sessionURLs: session), reportErrors: false) { doc, error in
            if let doc {
                completion(candidate, doc, failed)
            } else if let error, (error as NSError).code == NSUserCancelledError, (error as NSError).domain == NSCocoaErrorDomain {
                completion(nil, nil, failed)
            } else {
                self.openFirstReadable(of: sorted, failed: failed + [candidate], completion: completion)
            }
        }
    }

    private func open(_ url: URL, context: ImageDocument.OpeningContext, completion: @escaping (NSDocument?) -> Void) {
        open(url, context: context, reportErrors: true) { doc, _ in completion(doc) }
    }

    private func open(_ url: URL, context: ImageDocument.OpeningContext, reportErrors: Bool,
                      completion: @escaping (NSDocument?, (any Error)?) -> Void) {
        if let existing = document(for: url) {
            existing.showWindows()
            completion(existing, nil)
            return
        }
        // Prepare the document without displaying, so the opening context is set before
        // `makeWindowControllers` runs.
        openDocument(withContentsOf: url, display: false) { document, alreadyOpen, error in
            if let error {
                if reportErrors, (error as NSError).code != NSUserCancelledError { self.presentError(error) }
                completion(nil, error)
                return
            }
            guard let document = document as? ImageDocument else { completion(nil, CocoaError(.fileReadUnknown)); return }
            if !alreadyOpen {
                document.openingContext = context
                document.makeWindowControllers()
            }
            document.showWindows()
            completion(document, nil)
        }
    }
}
