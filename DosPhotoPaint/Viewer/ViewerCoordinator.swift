import AppKit
import Observation
import SwiftUI

/// Small observable UI state of the viewer features (read by SwiftUI overlays).
@Observable
final class ViewerUIState {
    var bannerDismissed = false
    var isComparing = false
}

/// Per-window glue for Photo Mode features: preloading, high-resolution upgrade on zoom,
/// animation playback, slideshow, image info, folder-access banner, compare-with-original,
/// drag-out and missing-file handling. `MainWindowController` only forwards a few events.
final class ViewerCoordinator {
    unowned let controller: MainWindowController
    let ui = ViewerUIState()
    let preloader = ImagePreloader()
    let animation = AnimationPlayer()
    lazy var slideshow = SlideshowController(controller: controller)
    lazy var info = ImageInfoPanelController(controller: controller)
    let browser = ImageBrowserModel()

    private var highResTask: Task<Void, Never>?
    private var bannerHost: NSView?
    private var bannerFolder: URL?

    private var state: WindowState { controller.state }
    private var session: BrowsingSession { controller.session }
    private var settings: AppSettings { controller.settings }
    private var canvasView: CanvasView { controller.canvasView }

    init(controller: MainWindowController) {
        self.controller = controller
        controller.session.onChange = { [weak self] in self?.sessionDidChange() }
        controller.canvasView.dragOutProvider = { [weak self] event in self?.beginDragOut(event) ?? false }
    }

    // MARK: - Events forwarded by MainWindowController

    /// The window now shows another document.
    func documentDidChange() {
        highResTask?.cancel()
        animation.stop()
        if ui.isComparing { ui.isComparing = false }
        if let folder = session.currentURL?.deletingLastPathComponent(), folder != bannerFolder {
            bannerFolder = folder
            ui.bannerDismissed = false
        }
        sessionDidChange()
        info.refresh()
        slideshow.documentDidChange()
    }

    /// The canvas view got new content for the current document (preview decoded or canvas shown).
    func contentDidShow() {
        slideshow.contentDidShow()
        startAnimationIfNeeded()
        scheduleHighResolution()
    }

    func magnificationDidChange() {
        scheduleHighResolution()
    }

    func modeDidChange() {
        if state.mode == .paint {
            state.showsImageBrowser = false
            animation.stop()
            highResTask?.cancel()
            slideshow.stop()
        } else {
            startAnimationIfNeeded()
            scheduleHighResolution()
        }
    }

    func windowWillClose() {
        highResTask?.cancel()
        animation.stop()
        slideshow.tearDown()
        info.close()
    }

    private func sessionDidChange() {
        controller.updateSessionStatus()
        preloader.update(session: session, maxPixelSize: controller.displayPixelBudget())
    }

    // MARK: - Navigation with missing-file handling

    nonisolated static func isMissing(_ url: URL) -> Bool {
        do {
            _ = try url.resourceValues(forKeys: [.isReadableKey])
            return false
        } catch let error as CocoaError {
            return error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
        } catch {
            return false
        }
    }

    /// Drops a file that vanished from disk from the session and tells the user briefly.
    func skipMissing(_ url: URL) {
        ImageCache.shared.remove(url)
        _ = session.remove(url)
        controller.updateSessionStatus()
        state.statusMessage = String(localized: "“\(url.lastPathComponent)” is no longer available and was skipped.", table: "Viewer")
    }

    /// Arrow keys / wheel at either end of the session (loop off) beep: the standard AppKit response to a
    /// navigation key that cannot act. Space and Escape never beep (handled as silent no-ops by the window).
    func step(_ delta: Int) {
        for _ in 0..<1000 {
            guard let url = session.url(movingBy: delta, loop: settings.photoLoopNavigation) else { break }
            if Self.isMissing(url) { skipMissing(url); continue }
            Task { await controller.navigate(to: url) }
            return
        }
        NSSound.beep()
    }

    func show(index: Int) {
        var i = index
        while let url = session.url(at: i) {
            if Self.isMissing(url) {
                skipMissing(url)
                i = min(i, session.urls.count - 1)
                continue
            }
            Task { await controller.navigate(to: url) }
            return
        }
    }

    // MARK: - High resolution on zoom

    /// Longest edge (pixels) that must be decoded so the image is sharp at the current zoom,
    /// or nil when the shown image is already good enough.
    nonisolated static func requiredLongestEdge(imageLongest: Int, fullLongest: CGFloat, fullShortest: CGFloat,
                                                magnification: CGFloat, backingScale: CGFloat) -> Int? {
        guard fullLongest > 0, fullShortest > 0 else { return nil }
        let needed = Int((fullLongest * min(1, magnification * backingScale)).rounded(.up))
        guard needed > imageLongest, imageLongest < Int(fullLongest) else { return nil }
        // Memory guard: never decode beyond ~100 megapixels for display.
        let pixels = fullLongest * fullShortest
        let cap = pixels > 100_000_000 ? Int(fullLongest * (100_000_000 / pixels).squareRoot()) : Int(fullLongest)
        let target = min(needed, cap)
        return target > imageLongest ? target : nil
    }

    private func scheduleHighResolution() {
        highResTask?.cancel()
        highResTask = nil
        guard state.mode == .photo, !ui.isComparing, !animation.isPlaying,
              let doc = controller.imageDocument, doc.canvas == nil, !doc.isAnimated,
              doc.fileURL != nil, case .preview(let image, let size) = canvasView.content else { return }
        let url = doc.fileURL!
        let scale = controller.window?.backingScaleFactor ?? 2
        guard Self.requiredLongestEdge(imageLongest: max(image.width, image.height), fullLongest: max(size.width, size.height),
                                       fullShortest: min(size.width, size.height), magnification: canvasView.magnification,
                                       backingScale: scale) != nil else { return }
        highResTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))  // debounce pinch / animated zoom
            guard let self, !Task.isCancelled else { return }
            // Re-evaluate: zoom may have changed during the delay.
            guard case .preview(let current, let size) = self.canvasView.content, self.controller.imageDocument === doc,
                  let target = Self.requiredLongestEdge(
                    imageLongest: max(current.width, current.height), fullLongest: max(size.width, size.height),
                    fullShortest: min(size.width, size.height), magnification: self.canvasView.magnification,
                    backingScale: self.controller.window?.backingScaleFactor ?? 2) else { return }
            let loaded = try? await Task.detached(priority: .userInitiated) {
                try ImageLoader.loadDisplayImage(url: url, maxPixelSize: target)
            }.value
            guard let loaded, !Task.isCancelled, self.controller.imageDocument === doc, doc.canvas == nil,
                  !self.ui.isComparing, case .preview(let now, let nowSize) = self.canvasView.content,
                  loaded.width > now.width || loaded.height > now.height else { return }
            // Same pixel size → same frame: zoom and scroll position are untouched.
            self.canvasView.content = .preview(loaded, pixelSize: nowSize)
        }
    }

    // MARK: - Animated images

    private func startAnimationIfNeeded() {
        guard settings.photoAutoplayGIF, state.mode == .photo, !ui.isComparing,
              let doc = controller.imageDocument, doc.isAnimated, let url = doc.fileURL,
              case .preview = canvasView.content, animation.playingURL != url else { return }
        animation.play(url: url, maxPixelSize: controller.displayPixelBudget()) { [weak self, weak doc] frame in
            guard let self, let doc, self.controller.imageDocument === doc, doc.canvas == nil,
                  self.state.mode == .photo, !self.ui.isComparing,
                  case .preview(_, let size) = self.canvasView.content else {
                self?.animation.stop()
                return
            }
            self.canvasView.content = .preview(frame, pixelSize: size)
        }
    }

    // MARK: - Compare with original

    func toggleCompare() {
        if ui.isComparing { endCompare(); return }
        guard let doc = controller.imageDocument, doc.canvas != nil, !doc.isProject, let url = doc.fileURL else { return }
        ui.isComparing = true
        animation.stop()
        highResTask?.cancel()
        state.statusMessage = String(localized: "Showing original", table: "Viewer")
        let budget = controller.displayPixelBudget()
        Task { [weak self] in
            let size = try? await Task.detached { try ImageLoader.info(for: url) }.value
            let image = try? await ImageCache.shared.displayImage(for: url, maxPixelSize: budget)
            guard let self, self.ui.isComparing, self.controller.imageDocument === doc else { return }
            guard let size, let image else {
                self.endCompare()
                self.state.statusMessage = String(localized: "The original file could not be read.", table: "Viewer")
                return
            }
            self.canvasView.content = .preview(image, pixelSize: CGSize(width: size.pixelWidth, height: size.pixelHeight))
        }
    }

    private func endCompare() {
        ui.isComparing = false
        if state.statusMessage == String(localized: "Showing original", table: "Viewer") { state.statusMessage = nil }
        if let model = controller.imageDocument?.canvas { canvasView.content = .canvas(model) }
    }

    // MARK: - Folder access banner

    func installOverlays(in container: NSView) {
        let host = NSHostingView(rootView: FolderAccessBanner(ui: ui, session: session, state: state, controller: controller))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.heightAnchor.constraint(equalToConstant: 34),
        ])
        bannerHost = host

        // Image browser over the canvas area.
        let browserHost = NSHostingView(rootView: ImageBrowserView(model: browser, session: session, settings: settings, controller: controller))
        browserHost.sizingOptions = []
        browserHost.translatesAutoresizingMaskIntoConstraints = false
        browserHost.isHidden = true
        container.addSubview(browserHost)
        let canvasArea = controller.scrollView
        NSLayoutConstraint.activate([
            browserHost.topAnchor.constraint(equalTo: canvasArea.topAnchor),
            browserHost.leadingAnchor.constraint(equalTo: canvasArea.leadingAnchor),
            browserHost.trailingAnchor.constraint(equalTo: canvasArea.trailingAnchor),
            browserHost.bottomAnchor.constraint(equalTo: canvasArea.bottomAnchor),
        ])
        observeContinuously(self) { me in
            let visible = me.state.showsImageBrowser && me.state.mode == .photo && !me.state.isSlideshowRunning
            if browserHost.isHidden == visible {
                browserHost.isHidden = !visible
                if !visible { me.controller.focusCanvasIfIdle() }
            }
        }
        // (Re)list when the browser opens, its options change, or the browsed folder / access changes.
        observeContinuously(self) { me in
            guard me.state.showsImageBrowser else { me.browser.cancel(); return }
            _ = (me.settings.photoBrowserIncludeSubfolders, me.settings.photoSortOrder,
                 me.session.folderURL, me.session.folderAccessDenied, me.session.isExplicit)
            me.reloadBrowser()
        }
        observeContinuously(self) { me in
            me.bannerHost?.isHidden = !(me.session.folderAccessDenied && !me.ui.bannerDismissed
                                        && me.state.mode == .photo && !me.state.isSlideshowRunning)
        }
    }

    func reloadBrowser() {
        guard state.showsImageBrowser else { return }
        browser.load(session: session, includeSubfolders: settings.photoBrowserIncludeSubfolders, order: settings.photoSortOrder)
    }

    // MARK: - Drag out

    /// Starts a drag session with the file (or the rendered image when edited) if the image fits
    /// in the view, i.e. there is nothing to pan. Returns false when the mouse drag should pan.
    private func beginDragOut(_ event: NSEvent) -> Bool {
        guard state.mode == .photo, !ui.isComparing, !state.isSlideshowRunning, !canvasView.canPan,
              let item = controller.sharingItems().first else { return false }
        let writer: NSPasteboardWriting
        switch item {
        case let url as URL: writer = url as NSURL
        case let image as NSImage: writer = image
        default: return false
        }
        guard case .preview(let cg, _) = canvasView.content else { return startDrag(writer, thumbnail: nil, event: event) }
        return startDrag(writer, thumbnail: cg, event: event)
    }

    private func startDrag(_ writer: NSPasteboardWriting, thumbnail: CGImage?, event: NSEvent) -> Bool {
        let item = NSDraggingItem(pasteboardWriter: writer)
        let point = canvasView.convert(event.locationInWindow, from: nil)
        let longest: CGFloat = 128
        var thumbSize = NSSize(width: longest, height: longest)
        var content: NSImage?
        if let cg = thumbnail {
            let ratio = CGFloat(cg.width) / CGFloat(max(cg.height, 1))
            thumbSize = ratio >= 1 ? NSSize(width: longest, height: longest / ratio) : NSSize(width: longest * ratio, height: longest)
            content = NSImage(cgImage: cg, size: thumbSize)
        } else if let canvas = controller.canvas, let flat = canvas.flattenedImage() {
            content = NSImage(cgImage: flat, size: thumbSize)
        }
        // The dragging frame is in view (image pixel) coordinates; convert from screen points.
        let mag = max(canvasView.magnification, 0.001)
        let frame = NSRect(x: point.x - thumbSize.width / 2 / mag, y: point.y - thumbSize.height / 2 / mag,
                           width: thumbSize.width / mag, height: thumbSize.height / mag)
        item.setDraggingFrame(frame, contents: content)
        canvasView.beginDraggingSession(with: [item], event: event, source: canvasView)
        return true
    }
}
