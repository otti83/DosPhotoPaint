import AppKit
import QuartzCore

/// Slideshow of the window's browsing session. One instance per window.
///
/// Timing is driven by `documentDidChange`: every time a new image is shown (by the slideshow or
/// manually) the next advance is scheduled after `slideshowInterval`, and the next image is
/// decoded into the cache immediately so the switch itself is instant.
final class SlideshowController {
    unowned let controller: MainWindowController
    /// Set when the window is closing (no full-screen restore then).
    var isClosing = false

    private var advanceTask: Task<Void, Never>?
    private var shuffle: SlideshowShuffle?
    private var pendingShuffleNext: URL?
    private var activity: NSObjectProtocol?
    private var enteredFullScreen = false
    private var restoreZoomAfterFullScreen = false
    private var transitionPending = false
    private var observers: [NSObjectProtocol] = []
    private var generator = SystemRandomNumberGenerator()

    private var state: WindowState { controller.state }
    private var settings: AppSettings { controller.settings }
    private var session: BrowsingSession { controller.session }
    var isRunning: Bool { state.isSlideshowRunning }

    init(controller: MainWindowController) {
        self.controller = controller
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .slideshowTogglePause, object: controller, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePause() }
        })
        observers.append(nc.addObserver(forName: .windowWillStopSlideshow, object: controller, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didResizeNotification] {
            observers.append(nc.addObserver(forName: name, object: controller.window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowGeometryChanged(name) }
            })
        }
    }

    /// Called when the window closes (the notification observers hold no strong reference anyway).
    func tearDown() {
        isClosing = true
        stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    // MARK: - Start / stop

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning, state.mode == .photo, session.currentURL != nil, let window = controller.window else { return }
        if controller.imageDocument?.isDocumentEdited == true {
            state.statusMessage = String(localized: "Save or revert your changes before starting a slideshow.", table: "Viewer")
            NSSound.beep()
            return
        }
        state.isSlideshowRunning = true
        state.isSlideshowPaused = false
        state.statusMessage = nil
        shuffle = settings.slideshowShuffle ? SlideshowShuffle(current: session.currentURL) : nil
        pendingShuffleNext = nil
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated],
                                                         reason: "Slideshow")
        controller.viewer.info.close()
        state.showsImageBrowser = false
        // Only the image: no toolbar or status bar while the show runs (restored in stop()).
        controller.updateToolbarVisibility()
        controller.applyViewSettings()
        if settings.slideshowFullScreen, !window.styleMask.contains(.fullScreen) {
            enteredFullScreen = true
            window.toggleFullScreen(nil)
        }
        // Hiding the toolbar/status bar changes the viewport only at the next layout pass.
        window.contentView?.layoutSubtreeIfNeeded()
        applyFit()
        scheduleAdvance()
    }

    func stop() {
        guard isRunning else { return }
        advanceTask?.cancel()
        advanceTask = nil
        state.isSlideshowRunning = false
        state.isSlideshowPaused = false
        shuffle = nil
        pendingShuffleNext = nil
        transitionPending = false
        controller.scrollView.layer?.removeAnimation(forKey: kCATransition)
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        NSCursor.setHiddenUntilMouseMoves(false)
        if !isClosing {
            controller.updateToolbarVisibility()
            controller.applyViewSettings()
        }
        if !isClosing, let window = controller.window {
            if enteredFullScreen, window.styleMask.contains(.fullScreen) {
                restoreZoomAfterFullScreen = true
                window.toggleFullScreen(nil)
            } else {
                window.contentView?.layoutSubtreeIfNeeded()   // chrome was just restored
                controller.applyInitialZoom()
            }
        }
        enteredFullScreen = false
    }

    func togglePause() {
        guard isRunning else { return }
        state.isSlideshowPaused.toggle()
        if state.isSlideshowPaused {
            advanceTask?.cancel()
            advanceTask = nil
        } else {
            scheduleAdvance()
        }
    }

    // MARK: - Events

    func documentDidChange() {
        if isRunning { scheduleAdvance() }
    }

    /// Called synchronously right after new content was assigned to the canvas view.
    func contentDidShow() {
        guard isRunning else { return }
        if transitionPending, settings.slideshowTransition == .dissolve {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.6
            controller.scrollView.wantsLayer = true
            controller.scrollView.layer?.add(transition, forKey: kCATransition)
        }
        transitionPending = false
        applyFit()
    }

    private func windowGeometryChanged(_ name: Notification.Name) {
        if name == NSWindow.didExitFullScreenNotification, restoreZoomAfterFullScreen {
            restoreZoomAfterFullScreen = false
            controller.applyInitialZoom()
        } else if isRunning {
            applyFit()
        }
    }

    private func applyFit() {
        let sv = controller.scrollView
        switch settings.slideshowFit {
        // Fill the screen: small images are enlarged too (aspect ratio kept).
        case .fit: sv.zoomToFit(.window, allowUpscale: true)
        case .actualSize: sv.setZoom(1); sv.scrollToCenter()
        }
        state.zoom = sv.magnification
    }

    // MARK: - Advancing

    private func nextURL() -> URL? {
        if shuffle != nil {
            if let pending = pendingShuffleNext, pending != session.currentURL, !ViewerCoordinator.isMissing(pending) { return pending }
            let next = shuffle?.next(all: session.urls, current: session.currentURL, loop: settings.slideshowLoop, using: &generator)
            pendingShuffleNext = next
            return next
        }
        return session.url(movingBy: 1, loop: settings.slideshowLoop)
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        advanceTask = nil
        guard isRunning, !state.isSlideshowPaused else { return }
        // Decode the next image now so the switch is instant.
        if let next = nextURL() {
            let budget = controller.displayPixelBudget()
            ImageCache.shared.prefetch(next, maxPixelSize: budget)
        }
        let interval = settings.slideshowInterval
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self?.advance()
        }
    }

    private func advance() async {
        guard isRunning, !state.isSlideshowPaused else { return }
        if controller.imageDocument?.isDocumentEdited == true {
            stop()
            state.statusMessage = String(localized: "Slideshow stopped because the image has unsaved changes.", table: "Viewer")
            return
        }
        var target: URL?
        for _ in 0..<200 {
            guard let candidate = nextURL() else { break }
            if ViewerCoordinator.isMissing(candidate) {
                pendingShuffleNext = nil
                controller.viewer.skipMissing(candidate)
                continue
            }
            target = candidate
            break
        }
        guard let target else {
            // Single image with looping simply stays on screen; otherwise the show is over.
            if settings.slideshowLoop, session.urls.count <= 1 { scheduleAdvance() } else { stop() }
            return
        }
        pendingShuffleNext = nil
        // Make sure the decode finished before switching (normally a cache hit).
        _ = try? await ImageCache.shared.displayImage(for: target, maxPixelSize: controller.displayPixelBudget())
        guard isRunning, !state.isSlideshowPaused, !Task.isCancelled else { return }
        NSCursor.setHiddenUntilMouseMoves(true)
        transitionPending = true
        await controller.navigate(to: target)
        // If the switch failed (damaged file) no document change fired; keep the show going.
        if isRunning, !state.isSlideshowPaused, controller.imageDocument?.fileURL?.standardizedFileURL != target.standardizedFileURL {
            transitionPending = false
            scheduleAdvance()
        }
    }
}
