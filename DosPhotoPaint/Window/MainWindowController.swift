import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One document window. Owns the browsing session, the shared canvas view (used by both modes),
/// the tool instances and the side panels. Navigating in Photo Mode swaps the window's document.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let state = WindowState()
    let session: BrowsingSession
    let scrollView = CanvasScrollView(frame: .zero)
    let canvasView = CanvasView(frame: .zero)
    let toolSettings = ToolSettings.shared
    let settings = AppSettings.shared

    private(set) var splitViewController: NSSplitViewController!
    private(set) var paletteItem: NSSplitViewItem!
    private(set) var inspectorItem: NSSplitViewItem!
    private var statusBarHost: NSView!
    private var statusBarHeight: NSLayoutConstraint!
    /// Horizontal tool palette above the canvas (tool palette position "Top").
    private(set) var ribbonHost: NSView!
    private var ribbonHeight: NSLayoutConstraint!
    /// Frame strip under animated images (Photo Mode).
    private(set) var frameStripHost: NSView!
    private var frameStripHeight: NSLayoutConstraint!

    private var tools: [ToolKind: CanvasTool] = [:]
    private var currentToolKind: ToolKind?
    private(set) var toolContext: ToolContext?
    private var previewTask: Task<Void, Never>?
    private var documentObservers: [NSObjectProtocol] = []
    /// True until the first image of this window has been zoomed initially.
    private var needsInitialZoom = true
    /// Photo Mode features (preload, slideshow, info, …).
    lazy var viewer = ViewerCoordinator(controller: self)
    var toolbars: [WindowMode: NSToolbar] = [:]
    var modeControls: [NSSegmentedControl] = []

    var imageDocument: ImageDocument? { document as? ImageDocument }
    var canvas: CanvasModel? { imageDocument?.canvas }

    // MARK: - Init

    init(initialMode: WindowMode, sessionURLs: [URL]?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: true)
        window.minSize = NSSize(width: 480, height: 320)
        window.tabbingMode = .automatic
        window.isRestorable = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.toolbarStyle = .unified
        session = BrowsingSession(explicitURLs: sessionURLs)
        super.init(window: window)
        shouldCascadeWindows = true
        window.delegate = self
        state.mode = initialMode
        buildUI()
        applyModeUI(animated: false)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI construction

    private func buildUI() {
        guard let window else { return }
        scrollView.documentView = canvasView
        canvasView.delegate = self
        scrollView.wheelHandler = { [weak self] event in self?.handleWheel(event) ?? false }
        scrollView.onMagnificationChange = { [weak self] z in
            self?.state.zoom = z
            self?.viewer.magnificationDidChange()
        }

        // Centre: (tool ribbon) + canvas + status bar.
        let center = NSViewController()
        let container = NSView()
        center.view = container
        let status = NSHostingView(rootView: StatusBarView(state: state, controller: self))
        status.sizingOptions = []
        statusBarHost = status
        let ribbon = NSHostingView(rootView: ToolRibbonView(state: state, tools: toolSettings, controller: self))
        ribbon.sizingOptions = []
        ribbon.isHidden = true
        ribbonHost = ribbon
        let strip = NSHostingView(rootView: FrameStripView(player: viewer.animation, controller: self))
        strip.sizingOptions = []
        strip.isHidden = true
        frameStripHost = strip
        for v in [ribbon, scrollView, strip, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        statusBarHeight = status.heightAnchor.constraint(equalToConstant: settings.showStatusBar ? 24 : 0)
        ribbonHeight = ribbon.heightAnchor.constraint(equalToConstant: 0)
        frameStripHeight = strip.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            ribbon.topAnchor.constraint(equalTo: container.topAnchor),
            ribbon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            ribbon.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ribbonHeight,
            scrollView.topAnchor.constraint(equalTo: ribbon.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: strip.topAnchor),
            strip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: status.topAnchor),
            frameStripHeight,
            status.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBarHeight,
        ])

        let palette = NSHostingController(rootView: ToolPaletteView(state: state, tools: toolSettings, controller: self))
        let inspector = NSHostingController(rootView: InspectorView(state: state, tools: toolSettings, controller: self))

        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        paletteItem = NSSplitViewItem(viewController: palette)
        paletteItem.canCollapse = true
        paletteItem.minimumThickness = 52
        paletteItem.maximumThickness = 96
        paletteItem.holdingPriority = .init(260)
        let centerItem = NSSplitViewItem(viewController: center)
        centerItem.minimumThickness = 200
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.canCollapse = true
        inspectorItem.minimumThickness = 220
        inspectorItem.maximumThickness = 360
        inspectorItem.holdingPriority = .init(255)
        split.addSplitViewItem(paletteItem)
        split.addSplitViewItem(centerItem)
        split.addSplitViewItem(inspectorItem)
        split.splitView.autosaveName = "DosPhotoPaintMainSplit"
        splitViewController = split

        viewer.installOverlays(in: container)
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1120, height: 760))
        installToolbars()
        // Display settings (background, checkerboard, interpolation, status bar) follow changes made
        // anywhere — the Settings window included — for as long as this window lives.
        observeContinuously(self) { $0.applyViewSettings() }
        observeContinuously(self) { $0.updateFrameStrip() }
    }

    // MARK: - Document attachment

    override var document: AnyObject? {
        didSet {
            if oldValue !== document { documentDidChange(from: oldValue as? ImageDocument) }
        }
    }

    private func documentDidChange(from old: ImageDocument?) {
        previewTask?.cancel()
        previewTask = nil
        documentObservers.forEach(NotificationCenter.default.removeObserver)
        documentObservers.removeAll()
        if let old, let ctx = toolContext {
            canvasView.cancelToolGesture()
            if let kind = currentToolKind { tools[kind]?.deactivate(context: ctx) }
            _ = old
        }
        currentToolKind = nil   // the next document's context must activate the tool again
        toolContext = nil
        state.statusMessage = nil

        guard let doc = imageDocument else {
            canvasView.content = .none
            state.imageSize = nil
            state.canvasGeneration += 1
            return
        }
        documentObservers.append(NotificationCenter.default.addObserver(
            forName: .imageDocumentCanvasDidMaterialize, object: doc, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.documentCanvasDidChange() }
            })
        documentObservers.append(NotificationCenter.default.addObserver(
            forName: .imageDocumentFileDidChangeExternally, object: doc, queue: .main) { [weak self] note in
                let missing = note.userInfo?[ImageDocument.fileMissingKey] as? Bool ?? false
                MainActor.assumeIsolated { self?.documentFileDidChangeExternally(missing: missing) }
            })
        state.isEdited = doc.isDocumentEdited
        if let url = doc.fileURL { session.didShow(url) }
        updateSessionStatus()
        viewer.documentDidChange()
        if showCanvasIfAvailable(applyZoom: true) {
            viewer.contentDidShow()
        } else {
            loadPreview(for: doc)
        }
        if state.mode == .paint && !doc.isMaterialized {
            Task { await self.enterPaintMode() }
        }
    }

    /// The document gained a canvas, replaced it (revert of a project) or dropped it
    /// (revert of an image / external change): show what the document has now.
    private func documentCanvasDidChange() {
        guard let doc = imageDocument else { return }
        if showCanvasIfAvailable() { return }
        // Canvas dropped: the file on disk is shown again.
        canvasView.cancelToolGesture()
        if let ctx = toolContext, let kind = currentToolKind { tools[kind]?.deactivate(context: ctx) }
        currentToolKind = nil
        toolContext = nil
        state.statusMessage = nil
        if state.mode == .paint {
            Task { await self.enterPaintMode() }
        } else {
            loadPreview(for: doc)
        }
    }

    private func documentFileDidChangeExternally(missing: Bool) {
        state.statusMessage = missing
            ? String(localized: "The file was moved or deleted. Your copy stays open; use Save As to write it again.", table: "Documents")
            : nil
    }

    /// Switches the view to the editable canvas if the document has one. Keeps the zoom unless `applyZoom`
    /// is set (a different document is being shown).
    @discardableResult
    private func showCanvasIfAvailable(applyZoom: Bool = false) -> Bool {
        guard let doc = imageDocument, let model = doc.canvas else { return false }
        if case .canvas(let current) = canvasView.content, current === model { return true }
        previewTask?.cancel()
        canvasView.content = .canvas(model)
        state.imageSize = model.size
        state.canvasGeneration += 1
        // Keep the status size in sync with undo/redo and structural edits.
        observeContinuously(model) { [weak self] m in
            let size = m.size
            guard let self, self.canvasView.canvasModel === m else { return }
            if self.state.imageSize != size { self.state.imageSize = size }
        }
        // A replaced canvas (project revert): the tool still points at the old one.
        if let old = toolContext, let kind = currentToolKind { tools[kind]?.deactivate(context: old) }
        currentToolKind = nil
        toolContext = ToolContext(canvas: model, settings: toolSettings, view: canvasView, windowState: state)
        // A different image gets the configured initial zoom. The same image gaining its editable
        // canvas (entering Paint Mode, revert) keeps the zoom and scroll position the user has.
        if applyZoom || needsInitialZoom { applyZoomForNewImage() }
        syncTool()
        return true
    }

    /// Photo Mode display of an unmaterialized image.
    private func loadPreview(for doc: ImageDocument) {
        guard let url = doc.fileURL, let info = doc.sourceInfo else { return }
        let pixelSize = CGSize(width: info.pixelWidth, height: info.pixelHeight)
        state.imageSize = pixelSize
        let maxPixel = displayPixelBudget()
        state.isLoading = true
        // Large JPEG/HEIC sources need a full-size decode for a screen-sized preview, which takes
        // ~130 ms for 24 MP. Image I/O can decode at half size with DCT scaling in about a quarter
        // of that, so show that first and swap in the sharp version when it arrives (same pixel
        // size, so zoom and scroll are untouched). Skipped when the sharp image is already cached.
        let longest = max(info.pixelWidth, info.pixelHeight)
        let quickSize = Self.quickPreviewSize(sourceLongest: longest, budget: maxPixel)
        let cached = ImageCache.shared.cachedImage(for: url, maxPixelSize: maxPixel)
        let stage = PreviewStage()
        previewTask = Task { [weak self] in
            let sharp = Task { try? await ImageCache.shared.displayImage(for: url, maxPixelSize: maxPixel) }
            if cached == nil, let quickSize {
                let quick = try? await Task.detached(priority: .userInitiated) {
                    try ImageLoader.loadDisplayImage(url: url, maxPixelSize: quickSize)
                }.value
                if let quick, !stage.sharpReady, !Task.isCancelled, let self, self.imageDocument === doc, doc.canvas == nil {
                    self.state.isLoading = false
                    self.canvasView.content = .preview(quick, pixelSize: pixelSize)
                    self.applyZoomForNewImage()
                    self.viewer.contentDidShow()
                    stage.quickShown = true
                }
            }
            let image = await sharp.value
            stage.sharpReady = true
            guard let self, !Task.isCancelled, self.imageDocument === doc else { return }
            self.state.isLoading = false
            if doc.canvas != nil { return }  // materialized meanwhile
            if let image {
                self.canvasView.content = .preview(image, pixelSize: pixelSize)
                if !stage.quickShown {
                    self.applyZoomForNewImage()
                    self.viewer.contentDidShow()
                }
            } else if !stage.quickShown {
                self.canvasView.content = .none
                self.state.statusMessage = String(localized: "This image could not be displayed.", table: "Window")
            }
        }
    }

    /// State shared between the quick and the sharp stage of `loadPreview`.
    private final class PreviewStage {
        var quickShown = false
        var sharpReady = false
    }

    /// Longest edge for the quick first preview, or nil when a quick stage would not pay off
    /// (small sources decode fast anyway; the quick size must be well below the sharp one).
    nonisolated static func quickPreviewSize(sourceLongest: Int, budget: Int) -> Int? {
        guard sourceLongest >= 4096 else { return nil }
        let quick = sourceLongest / 2
        return quick * 4 <= min(sourceLongest, budget) * 3 ? quick : nil
    }

    /// Longest edge (pixels) worth decoding for display on this window's screen.
    func displayPixelBudget() -> Int { Self.displayPixelBudget(for: window?.screen) }

    /// Budget for a window that will appear on `screen` (nil → main screen).
    static func displayPixelBudget(for screen: NSScreen?) -> Int {
        let screen = screen ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let size = screen?.frame.size ?? CGSize(width: 2560, height: 1600)
        return Int(max(size.width, size.height) * scale)
    }

    private func applyZoomForNewImage() {
        window?.contentView?.layoutSubtreeIfNeeded()
        if needsInitialZoom || settings.photoZoomOnNavigate == .automatic {
            applyInitialZoom()
            needsInitialZoom = false
        }
    }

    func applyInitialZoom() {
        if state.mode == .paint {
            scrollView.zoomToFit(.window, allowUpscale: false)
            return
        }
        switch settings.photoInitialZoom {
        case .fitWindow: scrollView.zoomToFit(.window, allowUpscale: false)
        case .fitWidth: scrollView.zoomToFit(.width, allowUpscale: false)
        case .fitHeight: scrollView.zoomToFit(.height, allowUpscale: false)
        case .actualSize: scrollView.setZoom(1); scrollView.scrollToCenter()
        }
        state.zoom = scrollView.magnification
    }

    override func setDocumentEdited(_ dirtyFlag: Bool) {
        super.setDocumentEdited(dirtyFlag)
        state.isEdited = dirtyFlag
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        displayName
    }

    func updateSessionStatus() {
        if let pos = session.position {
            state.sessionPosition = pos
            window?.subtitle = session.urls.count > 1 ? "\(pos.index) / \(pos.count)" : ""
        } else {
            state.sessionPosition = nil
            window?.subtitle = ""
        }
    }

    // MARK: - Modes

    func setMode(_ mode: WindowMode) {
        guard mode != state.mode else { return }
        if mode == .paint {
            Task { await enterPaintMode() }
        } else {
            leavePaintMode()
        }
    }

    /// Materializes the canvas (off the main thread) and shows the Paint UI.
    func enterPaintMode() async {
        guard let doc = imageDocument else { return }
        if !doc.isMaterialized {
            state.isLoading = true
            state.statusMessage = String(localized: "Preparing image for editing…", table: "Window")
            defer { state.isLoading = false }
            do {
                try await doc.materializeCanvas()
            } catch {
                state.statusMessage = nil
                state.mode = .photo
                applyModeUI(animated: true)
                if let window { doc.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil) }
                return
            }
            state.statusMessage = nil
            if doc.isAnimated { informAnimationFlattened() }
        }
        guard imageDocument === doc else { return }
        showCanvasIfAvailable()
        state.mode = .paint
        applyModeUI(animated: true)
        syncTool()
    }

    private func leavePaintMode() {
        canvasView.cancelToolGesture()
        if let ctx = toolContext, let kind = currentToolKind { tools[kind]?.deactivate(context: ctx) }
        currentToolKind = nil
        state.mode = .photo
        applyModeUI(animated: true)
    }

    private func informAnimationFlattened() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Animated image", table: "Window")
        alert.informativeText = String(localized: "Only the first frame of this animation is edited. Saving will write a still image.", table: "Window")
        alert.beginSheetModal(for: window)
    }

    func applyModeUI(animated: Bool) {
        let paint = state.mode == .paint
        let collapseInspector = !paint || !state.showsInspector
        applyPaletteLayout(animated: animated)
        if animated {
            inspectorItem.animator().isCollapsed = collapseInspector
        } else {
            inspectorItem.isCollapsed = collapseInspector
        }
        window?.toolbar = paint ? paintToolbar : photoToolbar
        updateToolbarVisibility()
        syncModeControls()
        applyViewSettings()
        viewer.modeDidChange()
        canvasView.refreshCursor()
        canvasView.needsDisplay = true
        focusCanvasIfIdle()
    }

    /// Keyboard navigation (←/→/Home/End, tool keys, Space) needs the canvas to be the first
    /// responder; without this it would only become so after the first click. Never steals
    /// focus from a text field that is being edited.
    func focusCanvasIfIdle() {
        guard let window else { return }
        if window.firstResponder is NSText || window.firstResponder === canvasView { return }
        window.makeFirstResponder(canvasView)
    }

    /// Shows the frame strip while an animation is loaded in Photo Mode (not during a slideshow,
    /// over the image browser or while comparing).
    func updateFrameStrip() {
        let visible = state.mode == .photo && viewer.animation.frameCount > 1 && !state.isSlideshowRunning
            && !state.showsImageBrowser && !viewer.ui.isComparing
        guard frameStripHost.isHidden == visible else { return }
        frameStripHost.isHidden = !visible
        frameStripHeight.constant = visible ? FrameStripView.height : 0
    }

    /// Whether the tool palette is shown as the horizontal ribbon above the canvas (vs. the left pane).
    var usesTopToolRibbon: Bool { settings.paintToolPalettePosition == .top }

    /// Shows the tool palette in the configured place (top ribbon or left pane) in Paint Mode.
    func applyPaletteLayout(animated: Bool) {
        let visible = state.mode == .paint && state.showsToolPalette
        let top = usesTopToolRibbon
        let collapseLeft = !visible || top
        if animated { paletteItem.animator().isCollapsed = collapseLeft } else { paletteItem.isCollapsed = collapseLeft }
        let showRibbon = visible && top
        ribbonHost.isHidden = !showRibbon
        ribbonHeight.constant = showRibbon ? ToolRibbonView.height : 0
    }

    /// The toolbar follows the setting, except during a slideshow (nothing but the image is shown).
    func updateToolbarVisibility() {
        let visible = settings.showToolbar && !state.isSlideshowRunning
        if window?.toolbar?.isVisible != visible { window?.toolbar?.isVisible = visible }
    }

    /// Re-reads display settings (background, checkerboard, interpolation, status bar).
    func applyViewSettings() {
        let paint = state.mode == .paint
        scrollView.backgroundColor = paint ? NSColor.underPageBackgroundColor : settings.photoBackground.color
        canvasView.showsCheckerboard = paint || settings.photoCheckerboard
        canvasView.interpolation = paint ? .automatic : settings.photoInterpolation
        let showStatus = settings.showStatusBar && !state.isSlideshowRunning
        statusBarHeight.constant = showStatus ? 24 : 0
        statusBarHost.isHidden = !showStatus
    }

    // MARK: - Tools

    var activeTool: CanvasTool? {
        guard state.mode == .paint, toolContext != nil, !viewer.ui.isComparing else { return nil }
        syncTool()
        return currentToolKind.flatMap { tools[$0] }
    }

    /// Ensures the active tool instance matches `ToolSettings.tool`, deactivating the old one.
    private func syncTool() {
        guard state.mode == .paint, let ctx = toolContext else { return }
        let wanted = toolSettings.tool
        guard wanted != currentToolKind else { return }
        if let kind = currentToolKind { tools[kind]?.deactivate(context: ctx) }
        if tools[wanted] == nil { tools[wanted] = ToolFactory.make(wanted) }
        currentToolKind = wanted
        tools[wanted]?.activate(context: ctx)
        canvasView.refreshCursor()
        canvasView.needsDisplay = true
    }

    func activateTool(_ kind: ToolKind) {
        if state.mode != .paint { setMode(.paint) }
        toolSettings.tool = kind
        syncTool()
    }

    // MARK: - Navigation (Photo Mode)

    /// Shows `url` in this window, replacing the current document. Unsaved changes are never
    /// discarded silently: the standard save / don't save / cancel sheet is shown first.
    /// `resettingSession` replaces the browsing list by the new file's folder once navigation
    /// is certain (not cancelled by the save prompt).
    func navigate(to url: URL, resettingSession: Bool = false) async {
        let url = url.standardizedFileURL
        if let current = imageDocument, current.fileURL?.standardizedFileURL == url { return }
        if let current = imageDocument, current.windowControllers.count == 1, current.isDocumentEdited {
            guard await current.confirmCanClose() else { return }
        }
        if resettingSession { session.replace(with: [], current: nil) }
        let controller = DocumentController.shared
        let next: ImageDocument
        if let open = controller.document(for: url) as? ImageDocument {
            next = open
        } else {
            do {
                let type = try controller.typeForContents(of: url)
                next = try ImageDocument(contentsOf: url, ofType: type)
                controller.addDocument(next)
            } catch {
                session.didShow(url)
                updateSessionStatus()
                showLoadError(error, for: url)
                return
            }
        }
        let wasEdited = imageDocument?.isDocumentEdited ?? false
        if let current = imageDocument {
            current.removeWindowController(self)
            if current.windowControllers.isEmpty {
                // Changes were either saved or explicitly discarded in confirmCanClose().
                if wasEdited { current.updateChangeCount(.changeCleared) }
                current.close()
            }
        }
        next.addWindowController(self)
        synchronizeWindowTitleWithDocumentName()
    }

    private func showLoadError(_ error: Error, for url: URL) {
        if let current = imageDocument, current.windowControllers.count == 1, !current.isDocumentEdited {
            current.removeWindowController(self)
            current.close()
        }
        canvasView.content = .none
        state.imageSize = nil
        window?.title = url.lastPathComponent
        state.statusMessage = error.localizedDescription
    }

    func showImage(at index: Int) { viewer.show(index: index) }

    func step(_ delta: Int) { viewer.step(delta) }

    /// Replaces the browsing list (e.g. Finder opened several files into an existing window).
    func replaceSession(with urls: [URL], current: URL?) {
        session.replace(with: urls, current: current)
        updateSessionStatus()
    }

    // MARK: - Wheel

    private var navigateWheelAccumulator: CGFloat = 0

    private func handleWheel(_ event: NSEvent) -> Bool {
        let behavior: WheelBehavior = event.modifierFlags.contains(.command)
            ? settings.photoCommandWheel
            : (state.mode == .photo ? settings.photoWheel : .scroll)
        switch behavior {
        case .scroll:
            return false
        case .zoom:
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
            guard delta != 0 else { return true }
            let factor = pow(1.01, delta)
            let anchor: CGPoint? = settings.photoZoomAtCursor ? canvasView.convert(event.locationInWindow, from: nil) : nil
            scrollView.setZoom(scrollView.magnification * factor, anchor: anchor)
            return true
        case .navigate:
            guard state.mode == .photo else { return false }
            if event.phase == .began || event.phase == [] && event.momentumPhase == [] && !event.hasPreciseScrollingDeltas {
                navigateWheelAccumulator = 0
            }
            if event.momentumPhase != [] { return true }
            navigateWheelAccumulator += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 40
            if abs(navigateWheelAccumulator) >= 40 {
                step(navigateWheelAccumulator > 0 ? -1 : 1)
                navigateWheelAccumulator = 0
            }
            return true
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        viewer.windowWillClose()
        previewTask?.cancel()
        canvasView.cancelToolGesture()
        if let ctx = toolContext, let kind = currentToolKind { tools[kind]?.deactivate(context: ctx) }
        stopSlideshowIfRunning()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if window?.firstResponder === window { window?.makeFirstResponder(canvasView) }
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        canvasView.needsDisplay = true
    }

    /// Slideshow in full screen: let the menu bar and toolbar hide instead of staying on screen
    /// (the system setting "Automatically hide and show the menu bar" may otherwise keep it visible).
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        guard state.isSlideshowRunning else { return proposedOptions }
        return proposedOptions.union([.fullScreen, .autoHideDock, .autoHideMenuBar, .autoHideToolbar])
    }

    /// AppKit restores the toolbar visibility it saw when entering full screen; a slideshow hides the
    /// toolbar just before that, so re-apply the current rule after every transition.
    func windowDidEnterFullScreen(_ notification: Notification) { updateToolbarVisibility() }
    func windowDidExitFullScreen(_ notification: Notification) {
        updateToolbarVisibility()
        applyViewSettings()
    }

    func windowDidResize(_ notification: Notification) {
        updateCompactLayout()
    }

    /// Small windows: collapse the inspector first, then the palette, to keep the canvas usable.
    private func updateCompactLayout() {
        guard state.mode == .paint, let width = window?.frame.width else { return }
        if width < 760, !inspectorItem.isCollapsed { inspectorItem.isCollapsed = true }
        else if width >= 900, inspectorItem.isCollapsed, state.showsInspector { inspectorItem.isCollapsed = false }
        // The top ribbon scrolls horizontally, so only the left pane needs collapsing.
        guard !usesTopToolRibbon else { return }
        if width < 560, !paletteItem.isCollapsed { paletteItem.isCollapsed = true }
        else if width >= 620, paletteItem.isCollapsed, state.showsToolPalette { paletteItem.isCollapsed = false }
    }

    /// Hook for the slideshow controller (Viewer module).
    func stopSlideshowIfRunning() {
        NotificationCenter.default.post(name: .windowWillStopSlideshow, object: self)
    }
}

extension Notification.Name {
    /// Posted by a window controller when its slideshow must stop (window closing).
    static let windowWillStopSlideshow = Notification.Name("WindowWillStopSlideshow")
}

// MARK: - CanvasViewDelegate

extension MainWindowController: CanvasViewDelegate {
    var isPaintMode: Bool { state.mode == .paint }

    func canvasView(_ view: CanvasView, keyDown event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])

        if state.mode == .paint {
            if let tool = activeTool, let ctx = toolContext, tool.keyDown(event, context: ctx) { return true }
            if mods.isEmpty || mods == .shift {
                switch event.keyCode {
                case 51, 117: // Delete / Forward Delete
                    NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: self)
                    return true
                case 53: // Escape
                    if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
                    return true   // consumed even when idle: an unhandled key would beep
                case 49: return true   // Space without an active gesture is a no-op, not an error
                default: break
                }
                if mods.isEmpty, let kind = ToolKind.forShortcut(chars) { activateTool(kind); return true }
                switch chars {
                case "x": toolSettings.swapColors(); return true
                case "]": adjustToolSize(by: 1); return true
                case "[": adjustToolSize(by: -1); return true
                default: break
                }
            }
            return false
        }

        // Photo Mode
        guard mods.isEmpty else { return false }
        switch event.keyCode {
        case 123: step(-1); return true                       // ←
        case 124: step(1); return true                        // →
        case 115: showImage(at: 0); return true               // Home
        case 119: showImage(at: session.urls.count - 1); return true  // End
        case 49:                                              // Space: pause/resume a running slideshow or an animation, otherwise a silent no-op
            if state.isSlideshowRunning { NotificationCenter.default.post(name: .slideshowTogglePause, object: self) }
            else if viewer.animation.isPlaying { viewer.animation.togglePause() }
            return true
        case 53:                                              // Escape: stop slideshow / close browser / leave full screen, otherwise a silent no-op
            if state.isSlideshowRunning { stopSlideshowIfRunning() }
            else if state.showsImageBrowser { hideImageBrowser() }
            else if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
            return true
        default:
            return false
        }
    }

    func canvasView(_ view: CanvasView, keyUp event: NSEvent) -> Bool { false }

    func canvasView(_ view: CanvasView, doubleClickAt pixel: CGPoint) {
        switch settings.photoDoubleClick {
        case .toggleFitActual:
            let fit = scrollView.fitMagnification(.window, allowUpscale: false)
            if abs(scrollView.magnification - fit) < 0.001 {
                scrollView.setZoom(1, anchor: pixel, animated: true)
            } else {
                scrollView.setZoom(fit, anchor: pixel, animated: true)
            }
        case .toggleFullScreen:
            window?.toggleFullScreen(nil)
        case .none:
            break
        }
    }

    func canvasView(_ view: CanvasView, pointerMovedTo pixel: CGPoint?) {
        state.cursorPixel = pixel.map { CGPoint(x: floor($0.x), y: floor($0.y)) }
    }

    func canvasView(_ view: CanvasView, draggingEntered info: NSDraggingInfo) -> NSDragOperation {
        DropHandling.draggingOperation(info, controller: self)
    }

    func canvasView(_ view: CanvasView, performDrop info: NSDraggingInfo) -> Bool {
        DropHandling.performDrop(info, controller: self)
    }

    func canvasViewDraggingExited(_ view: CanvasView) {}

    func canvasView(_ view: CanvasView, menuFor event: NSEvent) -> NSMenu? {
        ContextMenus.menu(for: self, event: event)
    }

    func adjustToolSize(by direction: Int) {
        func step(_ v: Double) -> Double {
            let delta = max(1, (v * 0.1).rounded())
            return min(max(v + Double(direction) * delta, ToolSettings.sizeRange.lowerBound), ToolSettings.sizeRange.upperBound)
        }
        switch toolSettings.tool {
        case .pen: toolSettings.penWidth = step(toolSettings.penWidth)
        case .brush: toolSettings.brushSize = step(toolSettings.brushSize)
        case .eraser: toolSettings.eraserSize = step(toolSettings.eraserSize)
        case .shape: toolSettings.shapeLineWidth = step(toolSettings.shapeLineWidth)
        case .text: toolSettings.fontSize = min(max(toolSettings.fontSize + Double(direction) * 2, ToolSettings.fontSizeRange.lowerBound), ToolSettings.fontSizeRange.upperBound)
        default: NSSound.beep()
        }
        canvasView.needsDisplay = true
    }
}

extension Notification.Name {
    static let slideshowTogglePause = Notification.Name("SlideshowTogglePause")
}

// MARK: - Close confirmation helper

extension NSDocument {
    /// Async wrapper over `canClose(withDelegate:shouldClose:contextInfo:)` (shows the standard
    /// "Do you want to save the changes…" sheet when needed).
    func confirmCanClose() async -> Bool {
        await withCheckedContinuation { continuation in
            let helper = CloseConfirmationHelper(continuation)
            CloseConfirmationHelper.pending.insert(helper)
            canClose(withDelegate: helper, shouldClose: #selector(CloseConfirmationHelper.document(_:shouldClose:contextInfo:)), contextInfo: nil)
        }
    }
}

private final class CloseConfirmationHelper: NSObject {
    static var pending: Set<CloseConfirmationHelper> = []
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume(returning: shouldClose)
        continuation = nil
        Self.pending.remove(self)
    }
}
