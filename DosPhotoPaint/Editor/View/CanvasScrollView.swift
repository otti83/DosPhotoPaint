import AppKit

/// Keeps the document centred when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let docFrame = doc.frame
        if rect.width > docFrame.width { rect.origin.x = docFrame.midX - rect.width / 2 }
        if rect.height > docFrame.height { rect.origin.y = docFrame.midY - rect.height / 2 }
        return rect
    }
}

/// Zoom levels used by Zoom In / Zoom Out.
enum ZoomLevels {
    static let minimum: CGFloat = 0.1
    static let maximum: CGFloat = 32
    static let steps: [CGFloat] = [0.1, 0.125, 0.167, 0.25, 0.333, 0.5, 0.667, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32]

    static func next(after z: CGFloat) -> CGFloat { steps.first { $0 > z * 1.001 } ?? maximum }
    static func previous(before z: CGFloat) -> CGFloat { steps.last { $0 < z * 0.999 } ?? minimum }
    static func clamp(_ z: CGFloat) -> CGFloat { min(max(z, minimum), maximum) }

    /// Zoom slider mapping: position 0…1 ↔ zoom `minimum…maximum` on a logarithmic scale
    /// (equal slider distance = equal zoom ratio).
    static func sliderPosition(forZoom z: CGFloat) -> Double {
        let z = Double(clamp(z)), lo = Double(minimum), hi = Double(maximum)
        return log(z / lo) / log(hi / lo)
    }

    static func zoom(forSliderPosition t: Double) -> CGFloat {
        let t = min(max(t, 0), 1), lo = Double(minimum), hi = Double(maximum)
        return clamp(CGFloat(lo * pow(hi / lo, t)))
    }

    /// Parses user input such as "250", "250%" or " 12.5 % " into a clamped zoom factor; nil when not a number.
    static func zoom(fromPercentText text: String) -> CGFloat? {
        let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return clamp(CGFloat(value / 100))
    }
}

enum FitMode {
    case window, width, height
}

/// Scroll view hosting `CanvasView`. Zoom = `magnification` (handled natively for pinch).
final class CanvasScrollView: NSScrollView {
    /// Wheel handling decided by the window controller (mode + settings). Return true if consumed.
    var wheelHandler: ((NSEvent) -> Bool)?
    /// Called after the magnification changed (any source).
    var onMagnificationChange: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = CenteringClipView()
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = ZoomLevels.minimum
        maxMagnification = ZoomLevels.maximum
        drawsBackground = true
        usesPredominantAxisScrolling = false
        scrollerStyle = .overlay
        setAccessibilityLabel(String(localized: "Image", table: "Viewer"))
        NotificationCenter.default.addObserver(self, selector: #selector(magnificationDidChange),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: self)
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange),
                                               name: NSView.boundsDidChangeNotification, object: contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var lastReportedMagnification: CGFloat = 0

    @objc private func magnificationDidChange() { reportMagnification() }
    @objc private func boundsDidChange() { reportMagnification() }

    private func reportMagnification() {
        if abs(magnification - lastReportedMagnification) > 0.0001 {
            lastReportedMagnification = magnification
            onMagnificationChange?(magnification)
            documentView?.needsDisplay = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if wheelHandler?(event) == true { return }
        super.scrollWheel(with: event)
    }

    // MARK: Zoom API

    /// Visible area size in points (excluding overlay scrollers).
    var visibleSize: CGSize { contentView.bounds.size.applying(CGAffineTransform(scaleX: magnification, y: magnification)) }

    /// Magnification at which the whole document fits. `allowUpscale` false caps it at 100 %.
    func fitMagnification(_ mode: FitMode = .window, allowUpscale: Bool = false) -> CGFloat {
        guard let doc = documentView, doc.frame.width > 0, doc.frame.height > 0 else { return 1 }
        let avail = contentSize
        let sx = avail.width / doc.frame.width
        let sy = avail.height / doc.frame.height
        var z: CGFloat = switch mode {
        case .window: min(sx, sy)
        case .width: sx
        case .height: sy
        }
        if !allowUpscale { z = min(z, 1) }
        return ZoomLevels.clamp(z)
    }

    /// Sets the zoom keeping `anchor` (document coordinates) fixed on screen; nil → centre of view.
    func setZoom(_ z: CGFloat, anchor: CGPoint? = nil, animated: Bool = false) {
        let z = ZoomLevels.clamp(z)
        let center = anchor ?? CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                animator().setMagnification(z, centeredAt: center)
            } completionHandler: { [weak self] in Task { @MainActor in self?.reportMagnification() } }
        } else {
            setMagnification(z, centeredAt: center)
            reportMagnification()
        }
    }

    func zoomToFit(_ mode: FitMode = .window, allowUpscale: Bool = false) {
        guard let doc = documentView else { return }
        setMagnification(fitMagnification(mode, allowUpscale: allowUpscale), centeredAt: CGPoint(x: doc.bounds.midX, y: doc.bounds.midY))
        reportMagnification()
    }

    func scrollToCenter() {
        guard let doc = documentView else { return }
        let b = contentView.bounds
        contentView.scroll(to: CGPoint(x: doc.frame.midX - b.width / 2, y: doc.frame.midY - b.height / 2))
        reflectScrolledClipView(contentView)
    }

    /// Moves the content with the pointer. `d` is the pointer movement in window coordinates (y-up).
    func pan(byScreenDelta d: CGSize) {
        var origin = contentView.bounds.origin
        origin.x -= d.width / magnification
        // Flipped document: pointer moving up (d.height > 0) reveals content further down.
        origin.y += ((documentView?.isFlipped ?? true) ? 1 : -1) * d.height / magnification
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: origin, size: contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
    }
}
